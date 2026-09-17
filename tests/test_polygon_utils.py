"""Tests for nesting.geometry.polygon_utils."""

from __future__ import annotations

import math

import pytest
from shapely.geometry import Polygon

from nesting.geometry.entities import Arc, Circle, Pt
from nesting.geometry.polygon_utils import (
    arc_points,
    chain_rings,
    circle_points,
    dedupe_ring,
    ring_to_polygon,
    transform_polygon,
)


class TestArcPoints:
    def test_endpoints_exact(self):
        pts = arc_points(Arc(Pt(0, 0), 10, 0, 90), 0.1)
        assert pts[0].x == pytest.approx(10, abs=1e-9)
        assert pts[0].y == pytest.approx(0, abs=1e-9)
        assert pts[-1].x == pytest.approx(0, abs=1e-9)
        assert pts[-1].y == pytest.approx(10, abs=1e-9)

    def test_points_lie_on_arc(self):
        arc = Arc(Pt(5, -3), 42, 30, 210)
        for p in arc_points(arc, 0.05):
            assert math.hypot(p.x - arc.center.x, p.y - arc.center.y) == pytest.approx(
                arc.radius, abs=1e-9
            )

    def test_finer_tolerance_more_points(self):
        coarse = arc_points(Arc(Pt(0, 0), 10, 0, 90), 1.0)
        fine = arc_points(Arc(Pt(0, 0), 10, 0, 90), 0.01)
        assert len(fine) > len(coarse) >= 3

    def test_full_circle_span(self):
        pts = circle_points(Circle(Pt(0, 0), 5), 0.1)
        assert pts[0].x == pytest.approx(5, abs=1e-9)
        assert pts[0].y == pytest.approx(0, abs=1e-9)
        assert pts[-1].x == pytest.approx(5, abs=1e-9)
        assert pts[-1].y == pytest.approx(0, abs=1e-9)
        assert len(pts) >= 8

    def test_wraparound_span(self):
        # 270 -> 90 CCW spans 180 degrees
        pts = arc_points(Arc(Pt(0, 0), 1, 270, 90), 0.05)
        assert pts[-1].x == pytest.approx(0, abs=1e-9)
        assert pts[-1].y == pytest.approx(1, abs=1e-9)


class TestTransformPolygon:
    SQUARE = Polygon([(0, 0), (10, 0), (10, 10), (0, 10)])

    def test_translate(self):
        moved = transform_polygon(self.SQUARE, dx=5, dy=15)
        assert moved.bounds == (5, 15, 15, 25)

    def test_mirror_then_translate(self):
        mirrored = transform_polygon(self.SQUARE, dx=10, mirrored=True)
        assert mirrored.bounds == (0, 0, 10, 10)

    def test_mirror_rotate_translate(self):
        placed = transform_polygon(self.SQUARE, dx=20, dy=0, rotation_deg=90, mirrored=True)
        # mirror: x -> -x gives [-10,0]x[0,10]; rotate 90 CCW about origin
        # maps (x,y)->(-y,x): [-10,0]x[-10,0]; translate by (20,0): [10,20]x[-10,0]
        assert placed.bounds == (10, -10, 20, 0)

    def test_noop(self):
        assert transform_polygon(self.SQUARE).equals(self.SQUARE)


class TestChainRings:
    def test_square_from_four_segments(self):
        segs = [
            [Pt(0, 0), Pt(10, 0)],
            [Pt(10, 0), Pt(10, 10)],
            [Pt(0, 10), Pt(10, 10)],  # reversed on purpose
            [Pt(0, 0), Pt(0, 10)],  # reversed on purpose
        ]
        rings, leftovers = chain_rings(segs, 0.01)
        assert len(rings) == 1
        assert leftovers == []
        poly = ring_to_polygon(rings[0])
        assert poly is not None and poly.area == pytest.approx(100)

    def test_two_separate_squares(self):
        segs = [
            [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1), Pt(0, 0)],
            [Pt(5, 5), Pt(6, 5), Pt(6, 6), Pt(5, 6), Pt(5, 5)],
        ]
        rings, leftovers = chain_rings(segs, 0.01)
        assert len(rings) == 2 and not leftovers

    def test_open_chain_is_leftover(self):
        segs = [[Pt(0, 0), Pt(10, 0)], [Pt(10, 0), Pt(10, 10)]]
        rings, leftovers = chain_rings(segs, 0.01)
        assert rings == []
        assert len(leftovers) == 1


class TestRingToPolygon:
    def test_dedupe_and_scale(self):
        pts = [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1), Pt(0, 0), Pt(0, 0)]
        poly = ring_to_polygon(pts, scale=10.0)
        assert poly is not None
        assert poly.area == pytest.approx(100)
        assert poly.bounds == (0, 0, 10, 10)

    def test_bowtie_is_repaired(self):
        pts = [Pt(0, 0), Pt(10, 10), Pt(10, 0), Pt(0, 10)]
        poly = ring_to_polygon(pts)
        assert poly is not None  # repaired to the largest valid lobe
        assert poly.area > 0

    def test_degenerate_returns_none(self):
        assert ring_to_polygon([Pt(0, 0), Pt(1, 1)]) is None

    def test_dedupe_ring(self):
        pts = [Pt(0, 0), Pt(0, 0), Pt(5, 0), Pt(5, 5), Pt(0, 5), Pt(0, 0)]
        assert len(dedupe_ring(pts)) == 4
