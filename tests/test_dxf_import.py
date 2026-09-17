"""Tests for nesting.io.dxf_import (milestone M1)."""

from __future__ import annotations

import math

import pytest

from nesting import NestSettings, import_dxf


class TestBasicImport:
    def test_rect_with_hole_and_text(self, make_dxf):
        def build(msp, doc):
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (600, 0, 0, 0, 0), (600, 800, 0, 0, 0), (0, 800, 0, 0, 0)],
                close=True,
                dxfattribs={"layer": "PANEL"},
            )
            msp.add_circle((300, 400), 40, dxfattribs={"layer": "PANEL"})
            msp.add_text("PANEL-A", dxfattribs={"height": 20}).set_placement((50, 50))

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 1
        part = result.parts[0]
        assert part.quantity == 1
        assert part.layer == "PANEL"
        assert len(part.holes) == 1
        assert part.area == pytest.approx(600 * 800 - math.pi * 40**2, rel=1e-3)
        assert "PANEL-A" in part.text_meta
        assert part.bounds == (0, 0, 600, 800)  # normalized to origin

    def test_identical_rects_merge_into_quantity(self, make_dxf):
        def build(msp, doc):
            for i in range(3):
                x = i * 500
                msp.add_lwpolyline(
                    [
                        (x, 0, 0, 0, 0),
                        (x + 200, 0, 0, 0, 0),
                        (x + 200, 100, 0, 0, 0),
                        (x, 100, 0, 0, 0),
                    ],
                    close=True,
                    dxfattribs={"layer": "PART"},
                )

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 1
        assert result.parts[0].quantity == 3
        assert result.total_quantity == 3

    def test_open_lines_stitch_into_part(self, make_dxf):
        def build(msp, doc):
            msp.add_line((0, 0), (1000, 0))
            msp.add_line((1000, 0), (1000, 1000))
            msp.add_line((1000, 1000), (0, 1000))
            msp.add_line((0, 1000), (0, 0))

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 1
        assert result.parts[0].area == pytest.approx(1_000_000)

    def test_open_chain_cannot_close_warns(self, make_dxf):
        def build(msp, doc):
            msp.add_line((0, 0), (100, 0))
            msp.add_line((100, 0), (100, 100))

        result = import_dxf(make_dxf(build))
        assert result.parts == []
        assert any("open chain" in w for w in result.warnings)

    def test_empty_modelscape_yields_no_parts(self, make_dxf):
        result = import_dxf(make_dxf(lambda msp, doc: None))
        assert result.parts == []
        assert result.total_quantity == 0


class TestContainment:
    def test_island_inside_hole_becomes_separate_part(self, make_dxf):
        def build(msp, doc):
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (1000, 0, 0, 0, 0), (1000, 1000, 0, 0, 0), (0, 1000, 0, 0, 0)],
                close=True,
                dxfattribs={"layer": "L"},
            )
            msp.add_circle((500, 500), 300, dxfattribs={"layer": "L"})  # hole
            msp.add_lwpolyline(  # island inside the hole
                [
                    (450, 450, 0, 0, 0),
                    (550, 450, 0, 0, 0),
                    (550, 550, 0, 0, 0),
                    (450, 550, 0, 0, 0),
                ],
                close=True,
                dxfattribs={"layer": "L"},
            )

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 2
        outer = max(result.parts, key=lambda p: p.area)
        island = min(result.parts, key=lambda p: p.area)
        assert len(outer.holes) == 1
        assert island.area == pytest.approx(10_000)

    def test_parts_on_different_layers_stay_separate(self, make_dxf):
        def build(msp, doc):
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (100, 0, 0, 0, 0), (100, 100, 0, 0, 0), (0, 100, 0, 0, 0)],
                close=True,
                dxfattribs={"layer": "A"},
            )
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (100, 0, 0, 0, 0), (100, 100, 0, 0, 0), (0, 100, 0, 0, 0)],
                close=True,
                dxfattribs={"layer": "B"},
            )

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 2


class TestInserts:
    def test_block_inserts_merge_with_quantity(self, make_dxf):
        def build(msp, doc):
            blk = doc.blocks.new("SQUARE")
            blk.add_lwpolyline(
                [(0, 0, 0, 0, 0), (200, 0, 0, 0, 0), (200, 100, 0, 0, 0), (0, 100, 0, 0, 0)],
                close=True,
            )
            msp.add_blockref("SQUARE", (0, 0), dxfattribs={"layer": "PARTS"})
            msp.add_blockref("SQUARE", (500, 0), dxfattribs={"layer": "PARTS"})
            msp.add_blockref("SQUARE", (1000, 0), dxfattribs={"layer": "PARTS", "rotation": 90})

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 1
        part = result.parts[0]
        assert part.name == "SQUARE"
        assert part.quantity == 3  # rotated insert merges too
        assert part.layer == "PARTS"

    def test_block_text_attached(self, make_dxf):
        def build(msp, doc):
            blk = doc.blocks.new("PLATE")
            blk.add_lwpolyline(
                [(0, 0, 0, 0, 0), (300, 0, 0, 0, 0), (300, 300, 0, 0, 0), (0, 300, 0, 0, 0)],
                close=True,
            )
            blk.add_text("PLATE-300", dxfattribs={"height": 20}).set_placement((20, 150))
            msp.add_blockref("PLATE", (0, 0), dxfattribs={"layer": "PARTS"})

        result = import_dxf(make_dxf(build))
        assert "PLATE-300" in result.parts[0].text_meta


class TestUnits:
    def test_inches_are_scaled_to_mm(self, make_dxf):
        def build(msp, doc):
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (10, 0, 0, 0, 0), (10, 20, 0, 0, 0), (0, 20, 0, 0, 0)],
                close=True,
            )

        result = import_dxf(make_dxf(build, insunits=1))
        assert result.source_unit == "inches"
        assert result.scale_to_mm == pytest.approx(25.4)
        part = result.parts[0]
        assert part.width == pytest.approx(254, abs=0.5)
        assert part.height == pytest.approx(508, abs=0.5)

    def test_unitless_warns_and_assumes_mm(self, make_dxf):
        result = import_dxf(make_dxf(lambda msp, doc: None, insunits=0))
        assert result.source_unit == "unitless"
        assert any("$INSUNITS" in w for w in result.warnings)

    def test_unit_override(self, make_dxf):
        def build(msp, doc):
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (10, 0, 0, 0, 0), (10, 10, 0, 0, 0), (0, 10, 0, 0, 0)],
                close=True,
            )

        result = import_dxf(make_dxf(build, insunits=4), NestSettings(unit_override="cm"))
        assert result.parts[0].width == pytest.approx(100)

    def test_unknown_override_raises(self, make_dxf):
        path = make_dxf(lambda msp, doc: None)
        with pytest.raises(ValueError, match="unknown unit"):
            import_dxf(path, NestSettings(unit_override="parsecs"))


class TestCurvedEntities:
    def test_ellipse_and_spline(self, make_dxf):
        def build(msp, doc):
            msp.add_ellipse((0, 0), major_axis=(150, 0), ratio=80.0 / 150.0)
            msp.add_spline(
                fit_points=[(400, 0), (450, 120), (560, 160), (640, 80), (580, 0)]
            ).closed = True

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 2
        areas = sorted(p.area for p in result.parts)
        assert areas[1] == pytest.approx(math.pi * 150 * 80, rel=0.01)  # ellipse
        assert areas[0] > 0  # closed spline blob

    def test_bulged_polyline_door(self, make_dxf):
        def build(msp, doc):
            msp.add_lwpolyline(
                [(0, 0, 0, 0, 0), (400, 0, 0, 0, 0), (400, 300, 0, 0, 1), (0, 300, 0, 0, 0)],
                close=True,
                dxfattribs={"layer": "DOOR"},
            )

        result = import_dxf(make_dxf(build))
        part = result.parts[0]
        assert part.area == pytest.approx(400 * 300 + math.pi * 200**2 / 2, rel=1e-3)
        assert part.height == pytest.approx(500, abs=0.5)

    def test_arcs_and_lines_chain(self, make_dxf):
        def build(msp, doc):
            msp.add_line((1600, 0), (1900, 0), dxfattribs={"layer": "B"})
            msp.add_arc((1900, 100), 100, -90, 90, dxfattribs={"layer": "B"})
            msp.add_line((1900, 200), (1600, 200), dxfattribs={"layer": "B"})
            msp.add_arc((1600, 100), 100, 90, 270, dxfattribs={"layer": "B"})

        result = import_dxf(make_dxf(build))
        assert len(result.parts) == 1
        expected = 300 * 200 + math.pi * 100**2
        assert result.parts[0].area == pytest.approx(expected, rel=1e-3)


class TestRecovery:
    def test_damaged_file_is_recovered_with_warning(self, tmp_path):
        path = tmp_path / "damaged.dxf"
        path.write_text("0\nSECTION\n2\nHEADER\n0\nGARBAGE\n")
        result = import_dxf(path)
        assert any("recovered" in w for w in result.warnings)

    def test_non_dxf_file_raises_oserror(self, tmp_path):
        path = tmp_path / "not_a_dxf.txt"
        path.write_text("hello world, definitely not a dxf")
        with pytest.raises(OSError, match="not a DXF file"):
            import_dxf(path)
