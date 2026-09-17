"""Symmetry-first nesting strategy.

Arranges parts in mirrored or repeated patterns across the sheet,
prioritizing pattern regularity over raw material yield - deliberately the
opposite objective of :mod:`nesting.nesting.waste_first`.

v0.1 layout model ("mirrored pair rows"):

1. Every part with mirror permission is split into **mirrored pairs**:
   the part and its mirror placed side by side as one unit.
2. Units are shelf-packed in rows, largest first, left to right.
3. Odd rows swap the pair order (mirror on the left), producing a
   butterfly/repeating pattern down the sheet.
4. Deterministic unit order makes repeated sheets identical wherever the
   job allows (machine once, repeat N times).

The regular grid spacing costs material - which is exactly what the
comparison report is designed to expose.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..config import NestSettings
from ..geometry.part import Part
from .base import NestingResult, Placement, SheetLayout, Strategy
from .common import Variant, compute_offcuts, part_variants

_EPS = 1e-6


@dataclass(frozen=True)
class _Unit:
    """One shelf item: a mirrored pair or a single part instance."""

    part: Part
    variant: Variant
    mirror_variant: Variant  # same orientation mirrored (falls back to variant)
    mirrored_pair: bool
    spacing: float

    @property
    def width(self) -> float:
        if self.mirrored_pair:
            return 2 * self.variant.width + self.spacing
        return self.variant.width

    @property
    def height(self) -> float:
        return self.variant.height


class SymmetryFirstStrategy(Strategy):
    """Maximize pattern regularity, accepting extra waste."""

    name = "symmetry-first"

    def nest(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        spacing = settings.part_spacing
        usable_w = settings.usable_width
        usable_h = settings.usable_height

        units: list[_Unit] = []
        unplaced: list[Part] = []

        for part in sorted(parts, key=lambda p: (-p.height, -p.area, p.part_id)):
            variant, mirror_variant = self._base_variants(part, settings)
            if variant is None:
                unplaced.append(part)
                continue
            mirror_ok = mirror_variant is not None
            quantity = part.quantity
            pairs = quantity // 2 if mirror_ok else 0
            singles = quantity - 2 * pairs

            pair = _Unit(part, variant, mirror_variant or variant, True, spacing)
            single = _Unit(part, variant, mirror_variant or variant, False, spacing)
            if pair.width <= usable_w + _EPS:
                units.extend([pair] * pairs)
            else:  # the pair is too wide for the sheet: degrade to singles
                singles += 2 * pairs
            units.extend([single] * singles)

        # largest units first; identical parts stay together (deterministic)
        units.sort(key=lambda u: (-u.height, -u.width, u.part.part_id, not u.mirrored_pair))

        sheets: list[SheetLayout] = []
        all_placements: list[list[Placement]] = []
        x = y = row_h = 0.0
        row_index = 0
        current: list[Placement] = []

        for unit in units:
            if x > _EPS and x + unit.width > usable_w + _EPS:
                x = 0.0
                y += row_h + spacing
                row_h = 0.0
                row_index += 1
            if y + unit.height > usable_h + _EPS:
                sheets.append(SheetLayout(index=len(sheets) + 1, placements=current))
                all_placements.append(current)
                current = []
                x = y = row_h = 0.0
                row_index = 0
            ec = settings.edge_clearance
            current.extend(
                self._place_unit(unit, len(sheets) + 1, ec + x, ec + y, swap=row_index % 2 == 1)
            )
            x += unit.width + spacing
            row_h = max(row_h, unit.height)

        if current:
            sheets.append(SheetLayout(index=len(sheets) + 1, placements=current))
            all_placements.append(current)

        for sheet in sheets:
            sheet.offcuts = compute_offcuts(sheet.placements, settings)

        return NestingResult(
            strategy=self.name,
            settings=settings,
            sheets=sheets,
            unplaced=sorted(unplaced, key=lambda p: p.part_id),
        )

    def _base_variants(
        self, part: Part, settings: NestSettings
    ) -> tuple[Variant | None, Variant | None]:
        """(base variant, mirrored twin) preferring the unrotated orientation.

        The mirrored twin shares the base rotation; it is None when mirroring
        is disallowed or the mirrored orientation is geometrically identical
        to the base (symmetric part).
        """
        variants = part_variants(part, settings)
        base: Variant | None = None
        mirror: Variant | None = None
        for variant in variants:
            if (
                variant.width <= settings.usable_width + _EPS
                and variant.height <= settings.usable_height + _EPS
            ):
                if base is None and not variant.mirrored:
                    base = variant
                    if variant.rotation_deg != 0.0:
                        break  # unrotated does not fit: take the least rotation
                if (
                    mirror is None
                    and variant.mirrored
                    and base is not None
                    and abs(variant.rotation_deg - base.rotation_deg) < _EPS
                ):
                    mirror = variant
                    break
        if base is None:
            # unrotated and every rotation failed; nothing fits at all
            return None, None
        return base, mirror

    def _place_unit(
        self, unit: _Unit, sheet_index: int, x: float, y: float, swap: bool
    ) -> list[Placement]:
        """Place one unit with its bbox minimum corner at absolute (x, y)."""
        tx, ty = x, y
        v, m = unit.variant, unit.mirror_variant
        if not unit.mirrored_pair:
            return [v.placement(unit.part, sheet_index, tx, ty)]
        left, right = (m, v) if swap else (v, m)
        first = left.placement(unit.part, sheet_index, tx, ty)
        second_x = tx + unit.variant.width + unit.spacing
        second = right.placement(unit.part, sheet_index, second_x, ty)
        return [first, second]
