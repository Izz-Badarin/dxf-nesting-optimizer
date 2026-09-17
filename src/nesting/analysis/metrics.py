"""Metric computations for the comparative analysis.

Area metrics, sheet replication and the CNC handling factors. Full
definitions are documented in ``docs/metrics.md``.
"""

from __future__ import annotations

import math
from collections import Counter
from collections.abc import Sequence
from hashlib import sha256
from typing import TYPE_CHECKING

from shapely.geometry import Polygon
from shapely.ops import unary_union

from ..config import NestSettings

if TYPE_CHECKING:  # pragma: no cover - import for typing only
    from ..nesting.base import NestingResult, Placement, SheetLayout


def utilization_pct(total_part_area: float, sheet_count: int, sheet_area: float) -> float:
    """Net material utilization: true part area over total sheet area, percent."""
    if sheet_count <= 0 or sheet_area <= 0:
        return 0.0
    return 100.0 * total_part_area / (sheet_count * sheet_area)


def waste_pct(total_part_area: float, sheet_count: int, sheet_area: float) -> float:
    """Net waste percentage (100 - utilization), floored at zero."""
    return max(0.0, 100.0 - utilization_pct(total_part_area, sheet_count, sheet_area))


def sheet_signature(placements: Sequence[Placement]) -> str:
    """Stable signature of a sheet layout.

    Two sheets with the same signature are identical layouts (ArtCAM-style
    "Sheet 1 (3 copies)" merging). Position, rotation and mirror are rounded
    to 0.001 mm / degree so floating-point noise never splits identical sheets.
    """
    items = sorted(
        (
            placement.part.part_id,
            round(placement.x, 3),
            round(placement.y, 3),
            round(placement.rotation_deg, 3),
            placement.mirrored,
        )
        for placement in placements
    )
    return sha256(repr(items).encode("utf-8")).hexdigest()[:16]


def replication_efficiency(sheet_signatures: Sequence[str]) -> float:
    """Sheet replication efficiency in [0, 1].

    ``sum(group_size - 1) / (sheet_count - 1)`` over signature groups: 1.0
    means every sheet is an exact repeat of the first (machine once, repeat N
    times); a single-sheet job is trivially repeatable (1.0).
    """
    count = len(sheet_signatures)
    if count <= 1:
        return 1.0
    groups = Counter(sheet_signatures)
    return sum(size - 1 for size in groups.values()) / (count - 1)


def sheet_copy_counts(sheets: Sequence[SheetLayout]) -> list[int]:
    """Copy count per unique layout, in first-appearance order."""
    seen: dict[str, int] = {}
    for sheet in sheets:
        signature = sheet_signature(sheet.placements)
        seen[signature] = seen.get(signature, 0) + sheet.copies
    return list(seen.values())


# ---------------------------------------------------------------------------
# CNC handling factors
# ---------------------------------------------------------------------------


def _ring_direction_changes(coords) -> int:
    """Count direction changes along a coordinate ring (path complexity proxy)."""
    vectors = []
    for (x0, y0), (x1, y1) in zip(coords, coords[1:], strict=False):
        dx, dy = x1 - x0, y1 - y0
        if abs(dx) > 1e-12 or abs(dy) > 1e-12:
            vectors.append((dx, dy))
    if len(vectors) < 2:
        return 0
    changes = 0
    for a, b in zip(vectors, vectors[1:], strict=False):
        angle = math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])
        if abs(angle) > 1e-6:
            changes += 1
    return changes


def _rapid_travel(points: list[tuple[float, float]]) -> float:
    """Greedy nearest-neighbour tour length from the sheet origin (estimate)."""
    remaining = list(points)
    x, y = 0.0, 0.0
    total = 0.0
    while remaining:
        best_i = min(
            range(len(remaining)),
            key=lambda i: (math.hypot(remaining[i][0] - x, remaining[i][1] - y), i),
        )
        px, py = remaining.pop(best_i)
        total += math.hypot(px - x, py - y)
        x, y = px, py
    return total


def _common_line_opportunities(bboxes, min_shared: float = 10.0, eps: float = 0.05) -> int:
    """Count placement pairs whose bbox edges lie within ``eps`` of each other.

    These are candidates for single-pass (common-line) cutting when the
    part-to-part clearance allows the outlines to butt up to one kerf width.
    """
    count = 0
    for i in range(len(bboxes)):
        ax0, ay0, ax1, ay1 = bboxes[i]
        for j in range(i + 1, len(bboxes)):
            bx0, by0, bx1, by1 = bboxes[j]
            flush = (
                (abs(ax1 - bx0) <= eps or abs(bx1 - ax0) <= eps)
                and min(ay1, by1) - max(ay0, by0) >= min_shared
            ) or (
                (abs(ay1 - by0) <= eps or abs(by1 - ay0) <= eps)
                and min(ax1, bx1) - max(ax0, bx0) >= min_shared
            )
            if flush:
                count += 1
    return count


def compute_metrics(result: NestingResult, settings: NestSettings | None = None) -> dict:
    """All metrics for one nesting result (see docs/metrics.md for formulas)."""
    settings = settings or result.settings
    sheet = settings.sheet
    usable = settings.usable_rect

    sheet_count = len(result.sheets)
    signatures = [sheet_signature(s.placements) for s in result.sheets]
    total_part_area = result.total_part_area
    utilization = utilization_pct(total_part_area, sheet_count, sheet.area)

    cut_length = 0.0
    kerf_area = 0.0
    pierce_count = 0
    direction_changes = 0
    min_edge_clearance = math.inf
    common_line = 0
    skeleton_components = 0
    all_placed = result.total_placements > 0

    for sheet_layout in result.sheets:
        polygons: list[Polygon] = []
        bboxes = []
        entry_points: list[tuple[float, float]] = []
        for placement in sheet_layout.placements:
            outline = placement.polygon
            holes = placement.hole_polygons
            polygons.append(outline)
            bboxes.append(outline.bounds)
            entry_points.append((outline.exterior.coords[0][0], outline.exterior.coords[0][1]))

            perimeter = outline.length + sum(h.length for h in holes)
            cut_length += perimeter
            kerf_area += perimeter * settings.tool_diameter / 2.0
            pierce_count += 1 + len(holes)
            direction_changes += _ring_direction_changes(list(outline.exterior.coords))
            for h in holes:
                direction_changes += _ring_direction_changes(list(h.exterior.coords))

            minx, miny, maxx, maxy = outline.bounds
            clearance = min(minx, sheet.width - maxx, miny, sheet.height - maxy)
            min_edge_clearance = min(min_edge_clearance, clearance)

        common_line += _common_line_opportunities(bboxes, eps=max(0.05, settings.tool_diameter))
        if polygons:
            waste = usable.difference(unary_union(polygons))
            if waste.is_empty:
                components = 0
            elif waste.geom_type == "MultiPolygon":
                components = len(waste.geoms)
            else:
                components = 1
            skeleton_components += components

    rapid = 0.0
    for sheet_layout in result.sheets:
        entry_points = [
            (p.polygon.exterior.coords[0][0], p.polygon.exterior.coords[0][1])
            for p in sheet_layout.placements
        ]
        rapid += _rapid_travel(entry_points)

    gross_area = total_part_area + kerf_area
    gross_utilization = min(100.0, utilization_pct(gross_area, sheet_count, sheet.area))

    if not all_placed:
        min_edge_clearance = 0.0

    return {
        "placed_count": result.total_placements,
        "unplaced_count": sum(p.quantity for p in result.unplaced),
        "utilization_pct": round(utilization, 2),
        "utilization_gross_pct": round(gross_utilization, 2),
        "waste_pct": round(max(0.0, 100.0 - utilization), 2),
        "sheet_count": sheet_count,
        "unique_sheet_layouts": len(set(signatures)),
        "copy_counts": sheet_copy_counts(result.sheets),
        "replication_efficiency": round(replication_efficiency(signatures), 3),
        "total_cut_length_mm": round(cut_length, 1),
        "pierce_count": pierce_count,
        "rapid_travel_mm": round(rapid, 1),
        "direction_changes": direction_changes,
        "min_edge_clearance_mm": round(min_edge_clearance, 2)
        if math.isfinite(min_edge_clearance)
        else 0.0,
        "skeleton_components": skeleton_components,
        "skeleton_connected": sheet_count == 0
        or all(_sheet_skeleton_connected(sheet_layout, usable) for sheet_layout in result.sheets),
        "common_line_opportunities": common_line,
    }


def _sheet_skeleton_connected(sheet_layout: SheetLayout, usable: Polygon) -> bool:
    if not sheet_layout.placements:
        return True
    waste = usable.difference(unary_union([p.polygon for p in sheet_layout.placements]))
    if waste.is_empty:
        return True
    if waste.geom_type == "MultiPolygon":
        return len(waste.geoms) <= 1
    return True
