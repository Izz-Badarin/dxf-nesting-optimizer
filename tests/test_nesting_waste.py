"""Tests for the waste-first nesting engine (milestone M3)."""

from __future__ import annotations

import math

from shapely.geometry import Polygon

from nesting import NestSettings, Part
from nesting.nesting.common import (
    expand_instances,
    merge_identical_sheets,
    part_variants,
    validate_result,
)
from nesting.nesting.waste_first import WasteFirstStrategy


def rect_part(part_id: str, w: float, h: float, qty: int = 1, holes: int = 0) -> Part:
    outline = Polygon([(0, 0), (w, 0), (w, h), (0, h)])
    hole = Polygon(
        (w / 2 + 10 * math.cos(2 * math.pi * i / 12), h / 2 + 10 * math.sin(2 * math.pi * i / 12))
        for i in range(12)
    )
    return Part(
        part_id=part_id,
        name=part_id,
        outline=outline,
        holes=(hole,) * holes if holes else (),
        quantity=qty,
        can_mirror=True,
    )


def nest(parts, **kwargs):
    settings = NestSettings(**kwargs) if kwargs else NestSettings()
    return WasteFirstStrategy().timed_nest(parts, settings), settings


class TestWasteFirst:
    def test_simple_job_places_everything(self):
        result, settings = nest([rect_part("A", 300, 200, qty=12)])
        assert result.unplaced == []
        assert result.total_placements == 12
        assert len(result.sheets) >= 1
        assert validate_result(result, settings) == []

    def test_multi_sheet(self):
        result, settings = nest([rect_part("A", 600, 800, qty=12)])
        assert len(result.sheets) >= 2
        assert result.unplaced == []
        assert validate_result(result, settings) == []

    def test_oversized_part_reported_unplaced(self):
        result, settings = nest([rect_part("A", 2000, 2500, qty=1)])
        assert len(result.sheets) == 0
        assert [p.part_id for p in result.unplaced] == ["A"]
        assert result.unplaced[0].quantity == 1

    def test_rotation_fits_long_part(self):
        # 2000 mm long part fits a 2440 mm sheet only when rotated to vertical
        result, settings = nest([rect_part("A", 2000, 100, qty=1)])
        assert result.unplaced == []
        placement = result.sheets[0].placements[0]
        assert placement.rotation_deg == 90.0
        assert validate_result(result, settings) == []

    def test_spacing_and_edges_respected(self):
        result, settings = nest([rect_part("A", 300, 200, qty=10), rect_part("B", 150, 400, qty=6)])
        assert validate_result(result, settings) == []

    def test_determinism(self):
        parts = [rect_part("A", 300, 200, qty=8), rect_part("B", 500, 150, qty=5)]
        r1, _ = nest(parts)
        r2, _ = nest(parts)
        sig1 = [merge_identical_sheets(r1.sheets)[i].placements for i in range(len(r1.sheets))]
        sig2 = [merge_identical_sheets(r2.sheets)[i].placements for i in range(len(r2.sheets))]
        assert len(sig1) == len(sig2)
        for a, b in zip(sig1, sig2, strict=True):
            assert [(p.part.part_id, round(p.x, 6), round(p.y, 6)) for p in a] == [
                (p.part.part_id, round(p.x, 6), round(p.y, 6)) for p in b
            ]

    def test_higher_utilization_than_symmetry_on_rects(self):
        from nesting.nesting.symmetry_first import SymmetryFirstStrategy

        parts = [rect_part("A", 600, 800, qty=12), rect_part("B", 400, 300, qty=10)]
        settings = NestSettings()
        waste = WasteFirstStrategy().nest(parts, settings)
        sym = SymmetryFirstStrategy().nest(parts, settings)
        util = lambda r: 100 * r.total_part_area / (len(r.sheets) * settings.sheet.area)  # noqa: E731
        assert util(waste) > util(sym)
        assert waste.unplaced == [] and sym.unplaced == []

    def test_depth_3_includes_true_shape_run(self):
        parts = [rect_part("A", 250, 180, qty=20)]
        result, settings = nest(parts, calculation_depth=3)
        assert result.unplaced == []
        assert validate_result(result, settings) == []

    def test_grain_direction_blocks_rotation_and_mirror(self):
        part = rect_part("A", 2000, 100, qty=2)
        part.grain_angle = 0.0
        result, _ = nest([part])
        # the long part cannot rotate with grain lock -> unplaced
        assert [p.part_id for p in result.unplaced] == ["A"]


class TestVariants:
    def test_rect_variants_dedupe_mirror(self):
        part = rect_part("A", 300, 200)
        variants = part_variants(part, NestSettings())
        assert len(variants) == 2  # 0 and 90 degrees; mirror is identical
        assert {v.rotation_deg for v in variants} == {0.0, 90.0}

    def test_asymmetric_part_has_mirror_variants(self):
        outline = Polygon([(0, 0), (300, 0), (300, 40), (40, 40), (40, 300), (0, 300)])
        part = Part(part_id="L", name="L", outline=outline)
        variants = part_variants(part, NestSettings())
        rotations = {(v.rotation_deg, v.mirrored) for v in variants}
        assert (0.0, False) in rotations
        assert (0.0, True) in rotations

    def test_mirror_disabled_by_settings(self):
        outline = Polygon([(0, 0), (300, 0), (300, 40), (40, 40), (40, 300), (0, 300)])
        part = Part(part_id="L", name="L", outline=outline)
        variants = part_variants(part, NestSettings(allow_mirror=False))
        assert all(not v.mirrored for v in variants)

    def test_expand_instances_order(self):
        parts = [rect_part("B", 100, 100, qty=2), rect_part("A", 500, 500, qty=1)]
        instances = expand_instances(parts)
        assert [p.part_id for p in instances] == ["A", "B", "B"]
