"""DXF import: ezdxf document -> validated :class:`~nesting.geometry.part.Part` list.

Pipeline (milestone M1):

1. Read the file (with ``recover`` fallback for damaged DXF files).
2. Detect source units from ``$INSUNITS`` (or a user override) and scale to mm.
3. Explode INSERT block references into virtual entities.
4. Flatten curves (arcs, splines, ellipses, bulged polylines) with a
   sagitta tolerance.
5. Stitch open line/arc chains into closed rings.
6. Group rings with the even-odd containment rule: outermost rings become
   part outlines, rings inside them become holes, rings inside holes become
   islands (new parts) - mirroring ArtCAM's "group inside and outside of
   shapes" logic.
7. Attach TEXT/MTEXT that falls inside a part as part metadata.
8. Normalize outlines to the origin and merge geometrically identical parts
   into a single part with a quantity.

Anything that cannot be interpreted as a closed contour is reported as a
warning - geometry is never dropped silently.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from pathlib import Path

import ezdxf
from ezdxf import recover
from ezdxf.entities import DXFGraphic
from ezdxf.path import make_path
from shapely.affinity import translate as shp_translate
from shapely.geometry import Point, Polygon

from ..config import NestSettings
from ..geometry.entities import Pt
from ..geometry.part import Part
from ..geometry.polygon_utils import chain_rings, ring_to_polygon

#: $INSUNITS code -> (name, millimetres per unit)
UNITS: dict[int, tuple[str, float]] = {
    0: ("unitless", 1.0),
    1: ("inches", 25.4),
    2: ("feet", 304.8),
    3: ("miles", 1_609_344.0),
    4: ("millimeters", 1.0),
    5: ("centimeters", 10.0),
    6: ("meters", 1000.0),
    7: ("kilometers", 1e6),
    8: ("microinches", 2.54e-5),
    9: ("mils", 0.0254),
    10: ("yards", 914.4),
    11: ("angstroms", 1e-7),
    12: ("nanometers", 1e-6),
    13: ("micrometers", 1e-3),
    14: ("decimeters", 100.0),
    15: ("decameters", 1e4),
    16: ("hectometers", 1e5),
    17: ("gigameters", 1e12),
}

UNIT_ALIASES: dict[str, int] = {
    "unitless": 0,
    "none": 0,
    "in": 1,
    "inch": 1,
    "inches": 1,
    "ft": 2,
    "foot": 2,
    "feet": 2,
    "mi": 3,
    "mile": 3,
    "miles": 3,
    "mm": 4,
    "millimeter": 4,
    "millimeters": 4,
    "millimetre": 4,
    "millimetres": 4,
    "cm": 5,
    "centimeter": 5,
    "centimeters": 5,
    "centimetre": 5,
    "centimetres": 5,
    "m": 6,
    "meter": 6,
    "meters": 6,
    "metre": 6,
    "metres": 6,
    "km": 7,
    "kilometer": 7,
    "kilometers": 7,
    "kilometre": 7,
    "kilometres": 7,
    "yd": 10,
    "yard": 10,
    "yards": 10,
}

#: entity types that carry no nestable contour (counted, not imported)
_SKIP_TYPES = {
    "ATTRIB",
    "ATTDEF",
    "POINT",
    "HATCH",
    "DIMENSION",
    "3DFACE",
    "SOLID",
    "TRACE",
    "VIEWPORT",
    "IMAGE",
    "WIPEOUT",
    "MLEADER",
    "LEADER",
    "TOLERANCE",
    "TABLE",
    "INSERT",  # handled separately via virtual entities
}


@dataclass
class ImportResult:
    """Everything extracted from a DXF file."""

    parts: list[Part] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    source_unit: str = "millimeters"
    scale_to_mm: float = 1.0
    stats: dict[str, object] = field(default_factory=dict)

    @property
    def total_quantity(self) -> int:
        return sum(part.quantity for part in self.parts)

    def to_dict(self) -> dict[str, object]:
        """JSON-friendly representation (used by ``dxfnest info --json``)."""
        return {
            "parts": [
                {
                    "part_id": part.part_id,
                    "name": part.name,
                    "layer": part.layer,
                    "quantity": part.quantity,
                    "width": round(part.width, 3),
                    "height": round(part.height, 3),
                    "area": round(part.area, 3),
                    "holes": len(part.holes),
                    "bbox": [round(v, 3) for v in part.bounds],
                    "can_rotate": part.can_rotate,
                    "can_mirror": part.can_mirror,
                    "text_meta": list(part.text_meta),
                }
                for part in self.parts
            ],
            "total_quantity": self.total_quantity,
            "warnings": list(self.warnings),
            "source_unit": self.source_unit,
            "scale_to_mm": self.scale_to_mm,
            "stats": self.stats,
        }


@dataclass
class _Candidate:
    """An un-merged part candidate in world coordinates."""

    name: str
    layer: str
    outline: Polygon
    holes: tuple[Polygon, ...] = ()
    texts: tuple[str, ...] = ()


@dataclass
class _Node:
    poly: Polygon
    depth: int = 0
    parent: int = -1


def import_dxf(path: str | Path, settings: NestSettings | None = None) -> ImportResult:
    """Import a DXF file and return validated, merged parts."""
    settings = settings or NestSettings()
    path = Path(path)
    doc, warnings = _read_document(path)
    scale, unit_name = _unit_scale(doc, settings.unit_override, warnings)
    msp = doc.modelspace()

    tol = max(settings.curve_tolerance / scale, 1e-6)
    chain_tol = max(settings.chain_tolerance / scale, 1e-6)

    entity_counts: Counter[str] = Counter(e.dxftype() for e in msp)
    inserts = [e for e in msp if e.dxftype() == "INSERT"]
    others = [e for e in msp if e.dxftype() != "INSERT"]

    closed, open_segments, texts, unsupported = _flatten_entities(others, tol)
    stitched = _stitch(open_segments, closed, chain_tol, warnings)
    candidates = _candidates_from_rings(closed, scale, warnings)

    for insert in inserts:
        virtual = list(_virtual_entities(insert))
        v_closed, v_open, v_texts, v_unsupported = _flatten_entities(
            virtual, tol, layer_override=insert.dxf.layer
        )
        unsupported.update(v_unsupported)
        texts.extend(v_texts)
        stitched += _stitch(
            v_open, v_closed, chain_tol, warnings, context=f"block '{insert.dxf.name}'"
        )
        candidates += _candidates_from_rings(
            v_closed, scale, warnings, name_override=insert.dxf.name
        )

    unattached = _attach_texts(candidates, texts, scale)
    _normalize(candidates)
    parts = _merge_candidates(candidates)

    stats = {
        "dxf_version": doc.dxfversion,
        "source_unit": unit_name,
        "scale_to_mm": scale,
        "entity_counts": dict(entity_counts),
        "unsupported_entities": dict(unsupported),
        "closed_paths": sum(len(rings) for rings in closed.values()),
        "stitched_chains": stitched,
        "inserts": len(inserts),
        "raw_parts": len(candidates),
        "unique_parts": len(parts),
        "total_quantity": sum(part.quantity for part in parts),
        "unattached_texts": unattached,
    }
    return ImportResult(
        parts=parts,
        warnings=warnings,
        source_unit=unit_name,
        scale_to_mm=scale,
        stats=stats,
    )


def _read_document(path: Path) -> tuple[ezdxf.document.Drawing, list[str]]:
    try:
        return ezdxf.readfile(path), []
    except (ezdxf.DXFError, StopIteration) as exc:
        try:
            doc, auditor = recover.readfile(path)
        except (ezdxf.DXFError, StopIteration):
            raise ValueError(f"cannot read DXF file '{path}': {exc}") from exc
        return doc, [
            f"file damaged ({exc.__class__.__name__}); recovered with "
            f"{len(auditor.errors)} error(s) and {len(auditor.fixes)} fix(es)"
        ]


def _unit_scale(
    doc: ezdxf.document.Drawing, override: str | None, warnings: list[str]
) -> tuple[float, str]:
    if override is not None:
        code = UNIT_ALIASES.get(override.lower())
        if code is None:
            raise ValueError(f"unknown unit '{override}'")
    else:
        code = doc.header.get("$INSUNITS", 0)
    name, factor = UNITS.get(code, ("unknown", 1.0))
    if code == 0 and override is None:
        warnings.append("DXF has no unit information ($INSUNITS=0) - assuming millimeters")
    return factor, name


def _flatten_entities(
    entities: Iterable[DXFGraphic], tol: float, layer_override: str | None = None
) -> tuple[
    dict[str, list[list[Pt]]],
    dict[str, list[list[Pt]]],
    list[tuple[str, str, tuple[float, float]]],
    Counter[str],
]:
    """Flatten graphics into point sequences, grouped per layer.

    Returns (closed rings, open segments, text items, unsupported counters).
    """
    closed: dict[str, list[list[Pt]]] = defaultdict(list)
    open_: dict[str, list[list[Pt]]] = defaultdict(list)
    texts: list[tuple[str, str, tuple[float, float]]] = []
    unsupported: Counter[str] = Counter()

    for entity in entities:
        etype = entity.dxftype()
        if etype in ("TEXT", "MTEXT"):
            layer = layer_override or entity.dxf.layer
            insert = entity.dxf.insert
            texts.append((layer, _text_content(entity), (insert.x, insert.y)))
            continue
        if etype in _SKIP_TYPES:
            unsupported[etype] += 1
            continue
        flat = _flatten(entity, tol)
        if flat is None:
            unsupported[etype] += 1
            continue
        points, is_closed = flat
        (closed if is_closed else open_)[layer_override or entity.dxf.layer].append(points)
    return closed, open_, texts, unsupported


def _flatten(entity: DXFGraphic, tol: float) -> tuple[list[Pt], bool] | None:
    """Flatten one entity via its ezdxf path; None when unsupported."""
    try:
        path = make_path(entity)
    except (TypeError, ValueError):
        return None
    points = [Pt(v.x, v.y) for v in path.flattening(tol)]
    if len(points) < 2:
        return None
    is_closed = bool(path.is_closed)
    if not is_closed and entity.dxftype() == "SPLINE":
        # closed (periodic) splines: make_path() leaves the path open even
        # when the DXF closed flag is set - honor the flag ourselves
        is_closed = bool(getattr(entity, "closed", False))
    return points, is_closed


def _virtual_entities(insert: DXFGraphic) -> Iterator[DXFGraphic]:
    """Yield the flattened content of an INSERT (recursing nested inserts)."""
    for entity in insert.virtual_entities():  # type: ignore[attr-defined]
        if entity.dxftype() == "INSERT":
            yield from _virtual_entities(entity)
        else:
            yield entity


def _text_content(entity: DXFGraphic) -> str:
    if entity.dxftype() == "MTEXT":
        plain = getattr(entity, "plain_text", None)
        return (plain() if plain else entity.text).strip()  # type: ignore[attr-defined]
    return entity.dxf.text.strip()  # type: ignore[attr-defined]


def _stitch(
    open_segments: dict[str, list[list[Pt]]],
    closed: dict[str, list[list[Pt]]],
    tol: float,
    warnings: list[str],
    context: str = "layer",
) -> int:
    """Stitch open segments per layer into ``closed``; returns rings created."""
    stitched = 0
    for layer, segments in open_segments.items():
        rings, leftovers = chain_rings(segments, tol)
        stitched += len(rings)
        closed[layer].extend(rings)
        if leftovers:
            warnings.append(
                f"{context} '{layer}': {len(leftovers)} open chain(s) could not be "
                f"closed and were skipped"
            )
    return stitched


def _candidates_from_rings(
    rings_by_layer: dict[str, list[list[Pt]]],
    scale: float,
    warnings: list[str],
    name_override: str | None = None,
) -> list[_Candidate]:
    """Convert rings into part candidates using even-odd containment."""
    candidates: list[_Candidate] = []
    for layer, rings in rings_by_layer.items():
        polygons: list[Polygon] = []
        dropped = 0
        for ring in rings:
            poly = ring_to_polygon(ring, scale)
            if poly is None:
                dropped += 1
            else:
                polygons.append(poly)
        if dropped:
            warnings.append(f"layer '{layer}': {dropped} degenerate contour(s) skipped")
        for outline, holes in _group_containment(polygons):
            valid_holes = tuple(
                hole for hole in holes if hole.within(outline) and hole.area < outline.area
            )
            candidates.append(
                _Candidate(
                    name=name_override or layer, layer=layer, outline=outline, holes=valid_holes
                )
            )
    return candidates


def _group_containment(polys: list[Polygon]) -> list[tuple[Polygon, list[Polygon]]]:
    """Even-odd containment grouping.

    Depth 0 rings are part outlines; odd-depth rings are holes of their
    immediate (even-depth) parent; even-depth rings deeper than 0 are islands,
    i.e. separate parts.
    """
    if not polys:
        return []
    nodes = [_Node(poly=poly) for poly in sorted(polys, key=lambda p: p.area, reverse=True)]
    for i, node in enumerate(nodes):
        bi = node.poly.bounds
        for j in range(i):
            bj = nodes[j].poly.bounds
            bbox_contains = bj[0] <= bi[0] and bj[1] <= bi[1] and bj[2] >= bi[2] and bj[3] >= bi[3]
            if bbox_contains and nodes[j].poly.contains(node.poly):
                node.depth = nodes[j].depth + 1
                node.parent = j
    entries: dict[int, list] = {}
    result: list[list] = []
    for i, node in enumerate(nodes):
        if node.depth % 2 == 0:
            entries[i] = [node.poly, []]
            result.append(entries[i])
    for node in nodes:
        if node.depth % 2 == 1 and node.parent >= 0:
            entries[node.parent][1].append(node.poly)
    return [(outline, holes) for outline, holes in result]


def _attach_texts(
    candidates: list[_Candidate],
    texts: list[tuple[str, str, tuple[float, float]]],
    scale: float,
) -> int:
    """Attach text items to the smallest candidate containing their point."""
    unattached = 0
    for layer, content, (tx, ty) in texts:
        point = Point(tx * scale, ty * scale)
        hit: _Candidate | None = None
        for candidate in candidates:
            if layer not in (candidate.layer, "0") and candidate.layer != "0":
                continue
            if candidate.outline.contains(point) and (
                hit is None or candidate.outline.area < hit.outline.area
            ):
                hit = candidate
        if hit is None:
            unattached += 1
        elif content not in hit.texts:
            hit.texts = hit.texts + (content,)
    return unattached


def _normalize(candidates: list[_Candidate]) -> None:
    """Move each candidate so its bbox minimum corner sits at (0, 0)."""
    for candidate in candidates:
        minx, miny, _, _ = candidate.outline.bounds
        candidate.outline = shp_translate(candidate.outline, -minx, -miny)
        candidate.holes = tuple(shp_translate(hole, -minx, -miny) for hole in candidate.holes)


def _merge_candidates(candidates: list[_Candidate]) -> list[Part]:
    """Merge geometrically identical candidates into parts with quantities."""
    parts: list[Part] = []
    index_by_signature: dict[tuple, int] = {}
    ordered = sorted(candidates, key=lambda c: (c.layer, c.name, -c.outline.area, -len(c.holes)))
    for candidate in ordered:
        part = Part(
            name=candidate.name,
            outline=candidate.outline,
            holes=candidate.holes,
            layer=candidate.layer,
            text_meta=candidate.texts,
        )
        signature = part.signature
        if signature in index_by_signature:
            existing = parts[index_by_signature[signature]]
            existing.quantity += 1
            extra = tuple(t for t in candidate.texts if t not in existing.text_meta)
            if extra:
                existing.text_meta = existing.text_meta + extra
        else:
            index_by_signature[signature] = len(parts)
            parts.append(part)
    for i, part in enumerate(parts, start=1):
        part.part_id = f"P{i:03d}"
    return parts
