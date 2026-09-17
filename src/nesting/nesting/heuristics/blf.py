"""True-shape bottom-left-fill placement (BLF).

Each sheet keeps a set of anchor points; a part variant is placed at the
first feasible anchor in (y, x) order - the classic bottom-left position.
Collision tests run on true (buffered) outlines, not bounding boxes, so
curved and concave parts pack tighter than MaxRects can manage.
"""

from __future__ import annotations

from shapely.affinity import translate as shp_translate
from shapely.geometry import Polygon

from ...config import NestSettings
from ..common import Variant

_EPS = 1e-6
# overlap tolerance in mm^2: exact-touch placements of curved parts produce
# tiny buffer-polygon slivers (~1e-4 mm^2) that must not count as collisions
_OVERLAP_EPS = 0.01


class BlfSheet:
    """One sheet of the bottom-left-fill heuristic."""

    def __init__(self, settings: NestSettings) -> None:
        self.settings = settings
        self.usable_w = settings.usable_width
        self.usable_h = settings.usable_height
        self.ec = settings.edge_clearance
        #: placed collision shapes (absolute coordinates)
        self.placed: list[Polygon] = []
        self.placed_bboxes: list[tuple[float, float, float, float]] = []
        self.placed_area = 0.0
        #: anchors as (y, x) in usable coordinates, kept sorted
        self.anchors: list[tuple[float, float]] = [(0.0, 0.0)]

    def fits(self, variant: Variant) -> bool:
        return variant.width <= self.usable_w + _EPS and variant.height <= self.usable_h + _EPS

    def try_place(self, variant: Variant, collision: Polygon) -> tuple[float, float] | None:
        """First feasible anchor in (y, x) order, or None."""
        vw, vh = variant.width, variant.height
        if not self.fits(variant):
            return None
        for ay, ax in self.anchors:
            if ax < -_EPS or ay < -_EPS:
                continue
            if ax + vw > self.usable_w + _EPS or ay + vh > self.usable_h + _EPS:
                continue
            candidate = shp_translate(collision, self.ec + ax, self.ec + ay)
            if self._hits(candidate):
                continue
            return (ax, ay)
        return None

    def commit(self, variant: Variant, collision: Polygon, ax: float, ay: float) -> None:
        """Record a placement at usable-relative (ax, ay) and update anchors."""
        absolute = shp_translate(collision, self.ec + ax, self.ec + ay)
        self.placed.append(absolute)
        self.placed_bboxes.append(absolute.bounds)
        self.placed_area += collision.area

        # anchors sit at the corners of the variant bbox expanded by the full
        # part spacing, so a neighbour placed there touches exactly at the
        # required gap
        spacing = self.settings.part_spacing
        vw, vh = variant.width, variant.height
        x0, x1 = ax - spacing, ax + vw + spacing
        y0, y1 = ay - spacing, ay + vh + spacing
        fresh = {(y0, x1), (y1, x0), (y1, x1)}
        merged = set(self.anchors) | fresh
        # drop anchors that can never fit anything
        merged = {
            (ay_, ax_)
            for (ay_, ax_) in merged
            if ax_ <= self.usable_w + _EPS and ay_ <= self.usable_h + _EPS
        }
        self.anchors = sorted(merged)

    def _hits(self, candidate: Polygon) -> bool:
        cb = candidate.bounds
        for poly, bb in zip(self.placed, self.placed_bboxes, strict=True):
            if not (cb[0] < bb[2] and cb[2] > bb[0] and cb[1] < bb[3] and cb[3] > bb[1]):
                continue
            if candidate.intersection(poly).area > _OVERLAP_EPS:
                return True
        return False
