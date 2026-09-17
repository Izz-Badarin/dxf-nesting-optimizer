"""Tests for nesting.geometry.symmetry."""

from __future__ import annotations

import math

from shapely.affinity import rotate as shp_rotate
from shapely.affinity import scale as shp_scale
from shapely.geometry import Polygon

from nesting.geometry.symmetry import (
    is_mirror_symmetric,
    mirror_similarity,
    symmetry_axes,
)

SQUARE = Polygon([(0, 0), (100, 0), (100, 100), (0, 100)])
L_SHAPE = Polygon([(0, 0), (4, 0), (4, 1), (1, 1), (1, 4), (0, 4)])
ASYMMETRIC = Polygon([(0, 0), (7, 0), (7, 3), (5, 3), (6, 5), (2, 6), (0, 4)])


class TestSymmetryAxes:
    def test_square_has_four_axes(self):
        angles = [angle for angle, _ in symmetry_axes(SQUARE)]
        for expected in (0, 45, 90, 135):
            assert any(abs(a - expected) <= 1.0 for a in angles), f"missing axis {expected}"

    def test_l_shape_has_exactly_one_axis(self):
        axes = symmetry_axes(L_SHAPE)
        assert len(axes) == 1
        assert abs(axes[0][0] - 45.0) <= 1.0

    def test_asymmetric_polygon_has_no_axes(self):
        assert symmetry_axes(ASYMMETRIC) == []

    def test_circle_is_symmetric_everywhere(self):
        circle = Polygon(
            (50 + 30 * math.cos(2 * math.pi * i / 64), 50 + 30 * math.sin(2 * math.pi * i / 64))
            for i in range(64)
        )
        assert is_mirror_symmetric(circle)
        assert len(symmetry_axes(circle)) > 10


class TestMirrorSimilarity:
    def test_mirror_pair_is_detected(self):
        mirrored = shp_scale(L_SHAPE, xfact=-1.0, yfact=1.0, origin=(0, 0))
        assert mirror_similarity(L_SHAPE, mirrored) > 0.99

    def test_rotated_copy_is_not_a_mirror_pair(self):
        rotated = shp_rotate(ASYMMETRIC, 90, origin="centroid")
        assert mirror_similarity(ASYMMETRIC, rotated) < 0.9

    def test_self_similarity_of_asymmetric_shape_is_low(self):
        # an asymmetric shape is not its own mirror image
        assert mirror_similarity(ASYMMETRIC, ASYMMETRIC) < 0.9

    def test_identical_symmetric_shape_matches_any_way(self):
        assert mirror_similarity(SQUARE, shp_scale(SQUARE, -1, 1, origin=(0, 0))) > 0.99
