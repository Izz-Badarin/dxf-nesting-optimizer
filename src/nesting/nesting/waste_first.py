"""Waste-minimization nesting strategy.

Arranges parts purely to minimize unused sheet area, regardless of symmetry.

v0.1 engine: best-of-N heuristic search, deterministic.

* **MaxRects** (bounding-box level) with the best-area and short-side fit
  rules - fast and near-optimal for rectangular parts. Items are collision
  bounding boxes (part bbox grown by half the part spacing), so adjacent
  parts keep exactly the required gap.
* **True-shape bottom-left-fill** for curved/concave parts - collision on
  buffered true outlines. Included at calculation depth >= 3, or at depth
  >= 2 for smaller jobs (<= 100 instances) where the extra cost is cheap.

The run with the best (fewest unplaced, fewest sheets, highest utilization)
wins. Free rotation, no-fit polygons and simulated-annealing refinement
arrive with the phase-2 optimizer.
"""

from __future__ import annotations

from dataclasses import replace

from shapely.geometry import Polygon

from ..config import NestSettings
from ..geometry.part import Part
from .base import NestingResult, SheetLayout, Strategy
from .common import (
    Variant,
    compute_offcuts,
    expand_instances,
    part_variants,
    variant_fits_sheet,
)
from .heuristics.blf import BlfSheet
from .heuristics.maxrects import RULES, MaxRectsBin

_EPS = 1e-6


class WasteFirstStrategy(Strategy):
    """Minimize unused sheet area."""

    name = "waste-first"

    def nest(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        instances = expand_instances(parts)
        variants_by_part = {id(part): part_variants(part, settings) for part in parts}

        runs: list[NestingResult] = []
        for rule in RULES[: 1 if settings.calculation_depth < 2 else 2]:
            runs.append(self._maxrects_run(parts, instances, variants_by_part, settings, rule))
        include_blf = settings.calculation_depth >= 3 or (
            settings.calculation_depth >= 2 and len(instances) <= 100
        )
        if include_blf:
            runs.append(self._blf_run(parts, instances, variants_by_part, settings))

        if not runs:
            runs.append(self._empty_result(parts, settings))
        best = min(runs, key=lambda r: (len(r.unplaced), len(r.sheets), -self._utilization(r)))
        best.runtime_s = 0.0  # set by timed_nest
        return best

    # -- MaxRects -----------------------------------------------------------

    def _maxrects_run(
        self,
        parts: list[Part],
        instances: list[Part],
        variants_by_part: dict[int, list[Variant]],
        settings: NestSettings,
        rule: str,
    ) -> NestingResult:
        ec = settings.edge_clearance
        grow = settings.collision_grow

        # per part: (variant, collision-bbox width, collision-bbox height)
        item_data: dict[int, list[tuple[Variant, float, float]]] = {}
        for part in parts:
            data = []
            for variant in variants_by_part[id(part)]:
                if not variant_fits_sheet(variant, settings):
                    continue
                data.append((variant, variant.width + 2 * grow, variant.height + 2 * grow))
            item_data[id(part)] = data

        bins: list[MaxRectsBin] = []
        sheets: list[SheetLayout] = []
        placements: dict[int, list] = {}
        unplaced_count: dict[int, int] = {}

        for instance in instances:
            data = item_data[id(instance)]
            if not data:
                unplaced_count[id(instance)] = unplaced_count.get(id(instance), 0) + 1
                continue
            best = None  # ((score, bin, variant), bin_idx, variant_idx, x, y)
            for bi, b in enumerate(bins):
                for vi, (_variant, w, h) in enumerate(data):
                    if w > b.width + _EPS or h > b.height + _EPS:
                        continue
                    scored = b.best_score(w, h, rule)
                    if scored is None:
                        continue
                    score, x, y = scored
                    key = (score, bi, vi)
                    if best is None or key < best[0]:
                        best = (key, bi, vi, x, y)
            if best is None:
                bins.append(MaxRectsBin(settings.usable_width, settings.usable_height))
                sheets.append(SheetLayout(index=len(sheets) + 1))
                placements[len(sheets) - 1] = []
                bi = len(bins) - 1
                vi = next(
                    i
                    for i, (_, w, h) in enumerate(data)
                    if w <= bins[bi].width and h <= bins[bi].height
                )
                variant, w, h = data[vi]
                bins[bi].place(0.0, 0.0, w, h)
                x = y = 0.0
            else:
                _, bi, vi, x, y = best
                variant, w, h = data[vi]
                bins[bi].place(x, y, w, h)
            # the MaxRects item includes the grow margin on every side
            placements[bi].append(
                variant.placement(instance, sheets[bi].index, ec + x + grow, ec + y + grow)
            )

        return self._assemble(parts, instances, sheets, placements, unplaced_count, settings)

    # -- bottom-left fill ----------------------------------------------------

    def _blf_run(
        self,
        parts: list[Part],
        instances: list[Part],
        variants_by_part: dict[int, list[Variant]],
        settings: NestSettings,
    ) -> NestingResult:
        ec = settings.edge_clearance
        grow = settings.collision_grow
        usable_area = settings.usable_width * settings.usable_height

        collision_by_part: dict[int, list[tuple[Variant, Polygon, float]]] = {}
        for part in parts:
            data = []
            for variant in variants_by_part[id(part)]:
                if not variant_fits_sheet(variant, settings):
                    continue
                collision = variant.outline.buffer(grow, join_style="mitre")
                data.append((variant, collision, collision.area))
            collision_by_part[id(part)] = data

        blf_sheets: list[BlfSheet] = []
        sheets: list[SheetLayout] = []
        placements: dict[int, list] = {}
        unplaced_count: dict[int, int] = {}

        for instance in instances:
            data = collision_by_part[id(instance)]
            if not data:
                unplaced_count[id(instance)] = unplaced_count.get(id(instance), 0) + 1
                continue
            best = None  # ((sheet, y, x, variant), sheet_idx, variant_idx, ax, ay)
            for si, sheet in enumerate(blf_sheets):
                for vi, (variant, collision, area) in enumerate(data):
                    if sheet.placed_area + area > usable_area + _EPS:
                        continue
                    position = sheet.try_place(variant, collision)
                    if position is None:
                        continue
                    ax, ay = position
                    key = (si, ay, ax, vi)
                    if best is None or key < best[0]:
                        best = (key, si, vi, ax, ay)
            if best is None:
                # open a new sheet and use the first fitting variant
                fitting = next(
                    (i for i, (v, _, _) in enumerate(data) if variant_fits_sheet(v, settings)),
                    None,
                )
                if fitting is None:
                    unplaced_count[id(instance)] = unplaced_count.get(id(instance), 0) + 1
                    continue
                blf_sheets.append(BlfSheet(settings))
                sheets.append(SheetLayout(index=len(sheets) + 1))
                placements[len(sheets) - 1] = []
                si = len(blf_sheets) - 1
                vi = fitting
                ax = ay = 0.0
            else:
                _, si, vi, ax, ay = best
            variant, collision, _ = data[vi]
            blf_sheets[si].commit(variant, collision, ax, ay)
            placements[si].append(variant.placement(instance, sheets[si].index, ec + ax, ec + ay))

        return self._assemble(parts, instances, sheets, placements, unplaced_count, settings)

    # -- shared --------------------------------------------------------------

    def _assemble(
        self,
        parts: list[Part],
        instances: list[Part],
        sheets: list[SheetLayout],
        placements: dict[int, list],
        unplaced_count: dict[int, int],
        settings: NestSettings,
    ) -> NestingResult:
        for sheet in sheets:
            sheet.placements = placements.get(sheet.index - 1, [])
            sheet.offcuts = compute_offcuts(sheet.placements, settings)
        by_id = {id(part): part for part in parts}
        unplaced = [replace(by_id[pid], quantity=count) for pid, count in unplaced_count.items()]
        unplaced.sort(key=lambda p: p.part_id)
        return NestingResult(
            strategy=self.name, settings=settings, sheets=sheets, unplaced=unplaced
        )

    def _empty_result(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        return NestingResult(
            strategy=self.name,
            settings=settings,
            sheets=[],
            unplaced=sorted(parts, key=lambda p: p.part_id),
        )

    def _utilization(self, result: NestingResult) -> float:
        if not result.sheets:
            return 0.0
        area = result.settings.sheet.area
        return 100.0 * result.total_part_area / (len(result.sheets) * area)
