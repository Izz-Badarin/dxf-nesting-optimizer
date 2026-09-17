"""Tests for the symmetry-first nesting engine (milestone M4)."""

from __future__ import annotations

from shapely.geometry import Polygon

from nesting import NestSettings, Part
from nesting.analysis.metrics import replication_efficiency, sheet_signature
from nesting.nesting.common import merge_identical_sheets, validate_result
from nesting.nesting.symmetry_first import SymmetryFirstStrategy


def l_part(part_id: str, qty: int = 1) -> Part:
    outline = Polygon([(0, 0), (300, 0), (300, 40), (40, 40), (40, 300), (0, 300)])
    return Part(part_id=part_id, name=part_id, outline=outline, quantity=qty)


def rect_part(part_id: str, w: float, h: float, qty: int = 1) -> Part:
    outline = Polygon([(0, 0), (w, 0), (w, h), (0, h)])
    return Part(part_id=part_id, name=part_id, outline=outline, quantity=qty)


class TestSymmetryFirst:
    def test_mirrored_pairs_created(self):
        result = SymmetryFirstStrategy().nest([l_part("L", qty=6)], NestSettings())
        assert result.unplaced == []
        assert result.total_placements == 6
        mirrored = [p for p in result.sheets[0].placements if p.mirrored]
        assert len(mirrored) == 3  # every pair contributes one mirrored twin

    def test_no_mirror_when_disabled(self):
        result = SymmetryFirstStrategy().nest(
            [l_part("L", qty=4)], NestSettings(allow_mirror=False)
        )
        assert all(not p.mirrored for sheet in result.sheets for p in sheet.placements)
        assert result.unplaced == []

    def test_valid_layout(self):
        result = SymmetryFirstStrategy().nest(
            [l_part("L", qty=6), rect_part("R", 400, 250, qty=5)], NestSettings()
        )
        assert result.unplaced == []
        assert validate_result(result, result.settings) == []

    def test_repeated_sheets_are_identical(self):
        # 28 pairs of a 300x300 L: 7 rows fit per sheet -> 4 identical sheets
        part = l_part("L", qty=56)
        result = SymmetryFirstStrategy().nest([part], NestSettings())
        assert len(result.sheets) >= 2
        signatures = [sheet_signature(s.placements) for s in result.sheets]
        assert replication_efficiency(signatures) >= 0.9

    def test_copy_merging(self):
        part = l_part("L", qty=56)
        result = SymmetryFirstStrategy().nest([part], NestSettings())
        merged = merge_identical_sheets(result.sheets)
        assert sum(sheet.copies for sheet in merged) == len(result.sheets)
        if len(merged) < len(result.sheets):
            assert merged[0].copies > 1

    def test_oversized_part_unplaced(self):
        result = SymmetryFirstStrategy().nest([rect_part("BIG", 1500, 2600, qty=2)], NestSettings())
        assert [p.part_id for p in result.unplaced] == ["BIG"]
        assert result.unplaced[0].quantity == 2

    def test_grain_blocks_mirroring(self):
        part = l_part("L", qty=4)
        part.grain_angle = 0.0
        result = SymmetryFirstStrategy().nest([part], NestSettings())
        assert all(not p.mirrored for sheet in result.sheets for p in sheet.placements)
