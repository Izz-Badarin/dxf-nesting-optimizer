"""Polygon utilities: curve flattening, ring stitching, transforms, repair."""

from __future__ import annotations

import math

from shapely.affinity import rotate as shp_rotate
from shapely.affinity import scale as shp_scale
from shapely.affinity import translate as shp_translate
from shapely.geometry import MultiPolygon, Polygon

from .entities import Arc, Circle, Pt


def arc_points(arc: Arc, sagitta: float) -> list[Pt]:
    """Flatten an arc into points, guaranteeing a sagitta bound.

    The chord error of every segment is at most ``sagitta`` (in the same units
    as the radius).
    """
    span = (arc.end_angle - arc.start_angle) % 360.0
    if span == 0.0:
        span = 360.0
    radius = abs(arc.radius)
    if radius <= 0:
        return []
    sag = max(sagitta, 1e-6)
    ratio = min(1.0, sag / radius)
    max_step = 2.0 * math.acos(1.0 - ratio)
    segments = max(2, math.ceil(math.radians(span) / max_step))
    points: list[Pt] = []
    for i in range(segments + 1):
        angle = math.radians(arc.start_angle + span * i / segments)
        points.append(
            Pt(
                arc.center.x + radius * math.cos(angle),
                arc.center.y + radius * math.sin(angle),
            )
        )
    return points


def circle_points(circle: Circle, sagitta: float) -> list[Pt]:
    """Flatten a full circle into points with a sagitta bound."""
    return arc_points(Arc(circle.center, circle.radius, 0.0, 360.0), sagitta)


def transform_polygon(
    poly: Polygon,
    dx: float = 0.0,
    dy: float = 0.0,
    rotation_deg: float = 0.0,
    mirrored: bool = False,
) -> Polygon:
    """Apply, in order: mirror (about x=0) -> rotate (CCW about origin) -> translate.

    This is the placement convention used across the nesting engine: part
    outlines are normalized so their bbox minimum corner sits at (0, 0), so
    (dx, dy) is the sheet position of the part origin.
    """
    result = poly
    if mirrored:
        result = shp_scale(result, xfact=-1.0, yfact=1.0, origin=(0, 0))
    if rotation_deg:
        result = shp_rotate(result, rotation_deg, origin=(0, 0))
    if dx or dy:
        result = shp_translate(result, dx, dy)
    return result


def dedupe_ring(points: list[Pt], eps: float = 1e-9) -> list[Pt]:
    """Remove consecutive duplicates and a duplicated closing point."""
    out: list[Pt] = []
    for point in points:
        if not out or math.hypot(point.x - out[-1].x, point.y - out[-1].y) > eps:
            out.append(point)
    if len(out) > 1 and math.hypot(out[0].x - out[-1].x, out[0].y - out[-1].y) <= eps:
        out.pop()
    return out


def ring_to_polygon(points: list[Pt], scale: float = 1.0) -> Polygon | None:
    """Build a valid polygon from a point ring.

    Invalid (self-intersecting) rings are repaired with ``buffer(0)``; if the
    repair collapses the ring, ``None`` is returned. ``scale`` multiplies all
    coordinates (used for unit conversion to mm).
    """
    ring = dedupe_ring(points)
    if len(ring) < 3:
        return None
    poly = Polygon([(p.x, p.y) for p in ring])
    if scale != 1.0:
        poly = shp_scale(poly, xfact=scale, yfact=scale, origin=(0, 0))
    if poly.is_valid and poly.area > 0:
        return poly
    return _repair(poly)


def _repair(poly: Polygon) -> Polygon | None:
    fixed = poly.buffer(0)
    candidates = [g for g in getattr(fixed, "geoms", [fixed]) if g.area > 0]
    polygons = [g for g in candidates if g.geom_type == "Polygon"]
    if not polygons:
        return None
    return max(polygons, key=lambda g: g.area)


def chain_rings(segments: list[list[Pt]], tol: float) -> tuple[list[list[Pt]], list[list[Pt]]]:
    """Greedy-stitch open point sequences into closed rings.

    Two sequences join when an endpoint of one matches an endpoint of the other
    within ``tol`` (either orientation). A chain becomes a ring when its own
    endpoints meet within ``tol``.

    Returns ``(rings, leftovers)`` - leftovers are open chains that could not
    be closed.
    """

    def near(a: Pt, b: Pt) -> bool:
        return math.hypot(a.x - b.x, a.y - b.y) <= tol

    chains: list[list[Pt]] = [list(seg) for seg in segments if len(seg) >= 2]
    rings: list[list[Pt]] = []
    leftovers: list[list[Pt]] = []

    while chains:
        current = chains.pop(0)
        extended = True
        while extended:
            extended = False
            for i, other in enumerate(chains):
                if near(current[-1], other[0]):
                    current = current + other[1:]
                elif near(current[-1], other[-1]):
                    current = current + list(reversed(other))[1:]
                elif near(current[0], other[-1]):
                    current = other[:-1] + current
                elif near(current[0], other[0]):
                    current = list(reversed(other))[:-1] + current
                else:
                    continue
                chains.pop(i)
                extended = True
                break
        if len(current) >= 4 and near(current[0], current[-1]):
            rings.append(current)
        else:
            leftovers.append(current)
    return rings, leftovers


def largest_polygon(geom: Polygon | MultiPolygon) -> Polygon:
    """Return the polygon itself, or its largest component for a MultiPolygon."""
    if isinstance(geom, MultiPolygon):
        return max(geom.geoms, key=lambda g: g.area)
    return geom
