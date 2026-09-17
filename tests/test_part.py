"""Tests for nesting.geometry.part."""

from __future__ import annotations

import math

import pytest
from shapely.affinity import rotate as shp_rotate
from shapely.geometry import Polygon

from nesting.geometry.part import Part


def make_part() -> Part:
    outline = Polygon([(0, 0), (100, 0), (100, 50), (0, 50)])
    hole = Polygon(
        (50 + 10 * math.cos(2 * math.pi * i / 16), 25 + 10 * math.sin(2 * math.pi * i / 16))
        for i in range(16)
    )
    return Part(name="PLATE", outline=outline, holes=(hole,), layer="PANEL", quantity=3)


class TestPart:
    def test_area_subtracts_holes(self):
        part = make_part()
        # hole is a regular 16-gon inscribed in r=10: area = n/2 * r^2 * sin(2pi/n)
        hole_area = 16 / 2 * 10**2 * math.sin(2 * math.pi / 16)
        assert part.area == pytest.approx(100 * 50 - hole_area, rel=1e-6)

    def test_dimensions(self):
        part = make_part()
        assert part.width == pytest.approx(100)
        assert part.height == pytest.approx(50)

    def test_geometry_placement(self):
        part = make_part()
        placed = part.geometry(dx=1000, dy=2000, rotation_deg=90)
        # rotating the 100x50 plate by 90 degrees about the origin gives
        # [-50, 0] x [0, 100]; translating by (1000, 2000):
        assert placed.bounds == (950, 2000, 1000, 2100)

    def test_mirrored_geometry(self):
        part = make_part()
        mirrored = part.geometry(dx=100, mirrored=True)
        assert mirrored.bounds == (0, 0, 100, 50)

    def test_collision_shape_grows(self):
        part = make_part()
        assert part.collision_shape(5).area > part.outline.area
        assert part.collision_shape(0).equals(part.outline)

    def test_signature_is_rotation_invariant(self):
        a = Part(name="X", layer="L", outline=Polygon([(0, 0), (100, 0), (100, 50), (0, 50)]))
        b = Part(name="X", layer="L", outline=shp_rotate(a.outline, 90, origin=(0, 0)))
        assert a.signature == b.signature

    def test_signature_counts_holes(self):
        part = make_part()
        holeless = Part(name=part.name, layer=part.layer, outline=part.outline, holes=())
        assert part.signature != holeless.signature

    def test_signature_distinguishes_layers(self):
        a = Part(name="X", layer="L1", outline=Polygon([(0, 0), (10, 0), (10, 10), (0, 10)]))
        b = Part(name="X", layer="L2", outline=Polygon([(0, 0), (10, 0), (10, 10), (0, 10)]))
        assert a.signature != b.signature
