"""Shared nesting machinery: orientation variants, placement math, offcuts."""

from __future__ import annotations

from dataclasses import dataclass

from shapely.affinity import translate as shp_translate
from shapely.geometry import Polygon
from shapely.ops import unary_union

from ..analysis.metrics import sheet_signature
from ..config import NestSettings
from ..geometry.part import Part
from ..geometry.polygon_utils import transform_polygon
from .base import NestingResult, Placement, SheetLayout

#: leftover regions smaller than this (mm^2) are scrap, not reusable offcuts
MIN_OFFCUT_AREA = 2500.0

_EPS = 1e-6


@dataclass(frozen=True)
class Variant:
    """One allowed orientation of a part.

    ``outline`` is the mirrored + rotated outline normalized so its bbox
    minimum corner sits at (0, 0); ``(ox, oy)`` is the bbox minimum of the
    un-normalized transform, so a placement that puts the variant bbox at
    (tx, ty) uses ``Placement(x=tx-ox, y=ty-oy)``.
    """

    rotation_deg: float
    mirrored: bool
    outline: Polygon
    ox: float
    oy: float

    @property
    def width(self) -> float:
        minx, miny, maxx, maxy = self.outline.bounds
        return maxx - minx

    @property
    def height(self) -> float:
        minx, miny, maxx, maxy = self.outline.bounds
        return maxy - miny

    def placement(self, part: Part, sheet_index: int, tx: float, ty: float) -> Placement:
        """Placement whose variant bbox minimum corner lands at (tx, ty)."""
        return Placement(
            part=part,
            sheet_index=sheet_index,
            x=tx - self.ox,
            y=ty - self.oy,
            rotation_deg=self.rotation_deg,
            mirrored=self.mirrored,
        )


def part_variants(part: Part, settings: NestSettings) -> list[Variant]:
    """Deterministic, deduplicated list of allowed orientations.

    Rotations follow ``settings.rotation_step_deg``; mirroring follows the
    global toggle, the part flag and grain constraints. Geometrically
    identical orientations (e.g. a mirrored square) are deduplicated.
    """
    if part.grain_angle is not None:
        rotations = [0.0]
    else:
        steps = max(1, round(360.0 / settings.rotation_step_deg))
        rotations = [round(360.0 * i / steps, 6) for i in range(steps)]
    allow_mirror = settings.allow_mirror and part.can_mirror and part.grain_angle is None

    variants: list[Variant] = []
    seen_keys: set[tuple] = set()
    for rotation in rotations:
        for mirrored in (False, True) if allow_mirror else (False,):
            raw = transform_polygon(part.outline, 0.0, 0.0, rotation, mirrored)
            minx, miny, _, _ = raw.bounds
            outline = shp_translate(raw, -minx, -miny)
            key = _variant_key(outline)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            variants.append(Variant(rotation, mirrored, outline, minx, miny))
    return variants


def _variant_key(outline: Polygon) -> tuple:
    """Orientation-insensitive canonical form of a ring.

    Two simple polygons have the same key iff their boundary cycles visit
    the same vertices (in either direction) - which is exactly the identity
    we need when deduplicating rotation/mirror variants.
    """
    pts = [(round(x, 6), round(y, 6)) for x, y in outline.exterior.coords]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    if not pts:
        return ()

    def canon(sequence: list[tuple[float, float]]) -> tuple:
        start = min(range(len(sequence)), key=lambda i: sequence[i])
        return tuple(sequence[start:] + sequence[:start])

    return min(canon(pts), canon(list(reversed(pts))))


def usable_rect(settings: NestSettings) -> Polygon:
    """The usable sheet region (delegates to NestSettings.usable_rect)."""
    return settings.usable_rect


def variant_fits_sheet(variant: Variant, settings: NestSettings) -> bool:
    return (
        variant.width <= settings.usable_width + _EPS
        and variant.height <= settings.usable_height + _EPS
    )


def expand_instances(parts: list[Part]) -> list[Part]:
    """Flatten parts into placement instances, largest area first."""
    instances: list[Part] = []
    for part in sorted(parts, key=lambda p: (-p.area, p.part_id)):
        instances.extend([part] * part.quantity)
    return instances


def compute_offcuts(placements: list[Placement], settings: NestSettings) -> list[Polygon]:
    """Reusable leftover regions: usable area minus placed part outlines."""
    usable = usable_rect(settings)
    if not placements:
        return [usable]
    placed = unary_union([placement.polygon for placement in placements])
    waste = usable.difference(placed)
    if waste.is_empty:
        return []
    polys = list(waste.geoms) if waste.geom_type == "MultiPolygon" else [waste]
    polys = [p for p in polys if p.geom_type == "Polygon" and p.area >= MIN_OFFCUT_AREA]
    return sorted(polys, key=lambda p: (-p.area, p.bounds))


def merge_identical_sheets(sheets: list[SheetLayout]) -> list[SheetLayout]:
    """ArtCAM-style identical-sheet merging ("Sheet 1 (3 copies)").

    Sheets with the same placement signature are reported once with the copy
    count summed. Returns a new list; the input is not modified.
    """
    merged: list[SheetLayout] = []
    index_by_signature: dict[str, int] = {}
    for sheet in sheets:
        signature = sheet_signature(sheet.placements)
        if signature in index_by_signature:
            merged[index_by_signature[signature]].copies += sheet.copies
        else:
            index_by_signature[signature] = len(merged)
            merged.append(
                SheetLayout(
                    index=len(merged) + 1,
                    placements=list(sheet.placements),
                    copies=sheet.copies,
                    offcuts=list(sheet.offcuts),
                )
            )
    return merged


def placement_holes(placement: Placement) -> list[Polygon]:
    """The part's holes under the placement transform (see Placement.hole_polygons)."""
    return placement.hole_polygons


def validate_result(result: NestingResult, settings: NestSettings) -> list[str]:
    """Check a nesting result for overlaps, spacing and edge violations.

    Returns a list of human-readable issues (empty when valid). Mainly used
    by tests and debugging; engines guarantee these properties by design.
    """
    from ..analysis.metrics import utilization_pct  # local import avoids cycles

    issues: list[str] = []
    spacing = settings.part_spacing
    tolerance = 0.05  # mm; absorbs buffer-polygon noise on curved outlines
    sheet = settings.sheet
    for sheet_layout in result.sheets:
        polys = [p.polygon for p in sheet_layout.placements]
        for i in range(len(polys)):
            for j in range(i + 1, len(polys)):
                if polys[i].distance(polys[j]) < spacing - tolerance:
                    issues.append(
                        f"sheet {sheet_layout.index}: parts {i} and {j} violate spacing "
                        f"(gap {polys[i].distance(polys[j]):.3f} < {spacing})"
                    )
        for placement in sheet_layout.placements:
            minx, miny, maxx, maxy = placement.polygon.bounds
            if (
                minx < settings.edge_clearance - 1e-3
                or miny < settings.edge_clearance - 1e-3
                or maxx > sheet.width - settings.edge_clearance + 1e-3
                or maxy > sheet.height - settings.edge_clearance + 1e-3
            ):
                issues.append(
                    f"sheet {sheet_layout.index}: part {placement.part.part_id} "
                    f"violates edge clearance"
                )
    if result.sheets:
        util = utilization_pct(result.total_part_area, len(result.sheets), settings.sheet.area)
        if util > 100.0 + 1e-6:
            issues.append("utilization above 100%")
    return issues
