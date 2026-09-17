"""Symmetry detection: mirror axes and mirror-pair similarity.

Drives the symmetry-first nesting strategy (M4) and the comparison report:
parts that are mirror-symmetric or come in mirrored pairs are candidates for
mirrored/tiled sheet patterns.
"""

from __future__ import annotations

from shapely.affinity import rotate as shp_rotate
from shapely.affinity import scale as shp_scale
from shapely.affinity import translate as shp_translate
from shapely.geometry import Polygon


def _reflect_through_centroid(poly: Polygon, angle_deg: float) -> Polygon:
    """Reflect ``poly`` across the line through its centroid at ``angle_deg``.

    Reflection about a line at angle ``a`` through the origin is
    ``Rot(a) . MirrorXAxis . Rot(-a)`` where the x-axis mirror flips y.
    """
    cx, cy = poly.centroid.x, poly.centroid.y
    result = shp_translate(poly, -cx, -cy)
    result = shp_rotate(result, -angle_deg, origin=(0, 0))
    result = shp_scale(result, xfact=1.0, yfact=-1.0, origin=(0, 0))
    result = shp_rotate(result, angle_deg, origin=(0, 0))
    return shp_translate(result, cx, cy)


def symmetry_axes(
    poly: Polygon, area_tol: float = 0.005, step_deg: float = 1.0
) -> list[tuple[float, float]]:
    """Find mirror-symmetry axes through the centroid.

    Candidate axes are tested on a ``step_deg`` grid over [0, 180). An axis
    counts as symmetric when the symmetric area difference between the polygon
    and its reflection is at most ``area_tol`` of the polygon area.

    Returns a list of ``(angle_deg, mismatch_ratio)`` sorted by mismatch
    (best first).
    """
    area = poly.area
    if area <= 0:
        return []
    simplified = _simplify(poly)
    axes: list[tuple[float, float]] = []
    steps = max(1, round(180.0 / step_deg))
    for i in range(steps):
        angle = i * step_deg
        reflected = _reflect_through_centroid(simplified, angle)
        mismatch = simplified.symmetric_difference(reflected).area / area
        if mismatch <= area_tol:
            axes.append((angle, mismatch))
    return sorted(axes, key=lambda t: t[1])


def is_mirror_symmetric(poly: Polygon, area_tol: float = 0.005) -> bool:
    """True when the polygon has at least one mirror-symmetry axis."""
    return bool(symmetry_axes(poly, area_tol=area_tol))


def mirror_similarity(a: Polygon, b: Polygon, step_deg: float = 5.0) -> float:
    """Best overlap ratio between ``mirror(a)`` (any rotation) and ``b``.

    Both polygons are simplified, centroid-aligned and compared over a rotation
    grid. Returns 1.0 for a perfect mirror pair, lower values otherwise.
    """
    ma = _simplify(shp_scale(_simplify(a), xfact=-1.0, yfact=1.0, origin=(0, 0)))
    target = _simplify(b)
    ca, cb = ma.centroid, target.centroid
    ma = shp_translate(ma, -ca.x, -ca.y)
    target = shp_translate(target, -cb.x, -cb.y)
    denom = max(1e-12, (ma.area + target.area) / 2.0)
    best = 0.0
    steps = max(1, round(360.0 / step_deg))
    for i in range(steps):
        candidate = shp_rotate(ma, i * step_deg, origin=(0, 0))
        overlap = candidate.intersection(target).area
        best = max(best, overlap / denom)
    return min(1.0, best)


def _simplify(poly: Polygon) -> Polygon:
    """Simplify for fast symmetry math, keeping at least sub-micron tolerance."""
    minx, miny, maxx, maxy = poly.bounds
    tol = max(1e-4, 0.0005 * max(maxx - minx, maxy - miny))
    simplified = poly.simplify(tol)
    return simplified if simplified.area > 0 else poly
