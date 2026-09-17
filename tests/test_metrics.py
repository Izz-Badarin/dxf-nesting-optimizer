"""Tests for nesting.analysis.metrics."""

from __future__ import annotations

from shapely.geometry import Polygon

from nesting.analysis.metrics import (
    replication_efficiency,
    sheet_copy_counts,
    sheet_signature,
    utilization_pct,
    waste_pct,
)
from nesting.geometry.part import Part
from nesting.nesting.base import Placement, SheetLayout


def make_placement(part_id: str, x: float, y: float, rot: float = 0.0, mirror: bool = False):
    part = Part(part_id=part_id, outline=Polygon([(0, 0), (100, 0), (100, 100), (0, 100)]))
    return Placement(part=part, sheet_index=0, x=x, y=y, rotation_deg=rot, mirrored=mirror)


class TestAreaMetrics:
    def test_utilization(self):
        assert utilization_pct(1_000_000, 1, 2_000_000) == 50.0
        assert utilization_pct(2_976_800, 1, 2_976_800) == 100.0
        assert utilization_pct(0, 3, 1000.0) == 0.0

    def test_utilization_multi_sheet(self):
        assert utilization_pct(1_500_000, 2, 1_000_000) == 75.0

    def test_zero_sheets_safe(self):
        assert utilization_pct(100, 0, 1000) == 0.0

    def test_waste_complements_utilization(self):
        assert waste_pct(1_000_000, 1, 2_000_000) == 50.0
        assert waste_pct(5_000_000, 1, 2_000_000) == 0.0  # floored


class TestSheetSignature:
    def test_identical_layouts_same_signature(self):
        a = [make_placement("P001", 10, 20), make_placement("P002", 300, 400, rot=90)]
        b = [make_placement("P002", 300, 400, rot=90), make_placement("P001", 10, 20)]
        assert sheet_signature(a) == sheet_signature(b)

    def test_different_layouts_differ(self):
        a = [make_placement("P001", 10, 20)]
        b = [make_placement("P001", 10, 21)]
        assert sheet_signature(a) != sheet_signature(b)

    def test_mirror_matters(self):
        assert sheet_signature([make_placement("P001", 10, 20)]) != sheet_signature(
            [make_placement("P001", 10, 20, mirror=True)]
        )

    def test_floating_point_noise_ignored(self):
        a = [make_placement("P001", 10.0000001, 20.0)]
        b = [make_placement("P001", 10.0, 20.0)]
        assert sheet_signature(a) == sheet_signature(b)


class TestReplication:
    def test_single_sheet_is_trivially_repeatable(self):
        assert replication_efficiency(["a"]) == 1.0
        assert replication_efficiency([]) == 1.0

    def test_all_identical(self):
        assert replication_efficiency(["a", "a", "a"]) == 1.0

    def test_all_different(self):
        assert replication_efficiency(["a", "b", "c"]) == 0.0

    def test_partial(self):
        # two of three sheets identical: (2-1)/(3-1) = 0.5
        assert replication_efficiency(["a", "a", "b"]) == 0.5

    def test_copy_counts(self):
        sheets = [
            SheetLayout(index=1, placements=[make_placement("P001", 0, 0)]),
            SheetLayout(index=2, placements=[make_placement("P001", 0, 0)]),
            SheetLayout(index=3, placements=[make_placement("P002", 5, 5)]),
        ]
        assert sheet_copy_counts(sheets) == [2, 1]
