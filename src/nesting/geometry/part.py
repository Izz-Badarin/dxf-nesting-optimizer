"""The Part model: the unit of nesting.

A part is a normalized outer contour plus optional holes, with quantity,
metadata and placement constraints. Outlines are translated at import time so
the bbox minimum corner sits at (0, 0); placements therefore position the part
origin directly on the sheet.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from shapely.geometry import Polygon

from .entities import Entity
from .polygon_utils import transform_polygon


@dataclass
class Part:
    """A nestable part (one unique shape, possibly required in quantity)."""

    part_id: str = ""
    name: str = ""
    outline: Polygon = field(default_factory=lambda: Polygon())
    holes: tuple[Polygon, ...] = ()
    quantity: int = 1
    layer: str = ""
    text_meta: tuple[str, ...] = ()
    can_rotate: bool = True
    can_mirror: bool = True
    #: grain direction in degrees, or None when the part has no grain constraint
    grain_angle: float | None = None
    #: source entities kept for arc-preserving DXF export (M3)
    source_entities: tuple[Entity, ...] = ()

    @property
    def area(self) -> float:
        """True material area: outline minus holes."""
        return self.outline.area - sum(hole.area for hole in self.holes)

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        return self.outline.bounds

    @property
    def width(self) -> float:
        minx, miny, maxx, maxy = self.bounds
        return maxx - minx

    @property
    def height(self) -> float:
        minx, miny, maxx, maxy = self.bounds
        return maxy - miny

    def geometry(
        self, dx: float = 0.0, dy: float = 0.0, rotation_deg: float = 0.0, mirrored: bool = False
    ) -> Polygon:
        """Placed outline: mirror -> rotate -> translate (placement convention)."""
        return transform_polygon(self.outline, dx, dy, rotation_deg, mirrored)

    def collision_shape(self, grow: float) -> Polygon:
        """Outline grown by ``grow`` for overlap tests against other parts."""
        if grow <= 0:
            return self.outline
        return self.outline.buffer(grow, join_style="mitre")

    @property
    def signature(self) -> tuple:
        """Rotation-invariant identity used to merge identical parts.

        Two parts with the same signature are treated as copies of the same
        shape (heuristic: layer, area, sorted bbox size, vertex count, holes).
        """
        minx, miny, maxx, maxy = self.bounds
        w, h = maxx - minx, maxy - miny
        return (
            self.name,
            self.layer,
            round(self.outline.area, 3),
            round(min(w, h), 3),
            round(max(w, h), 3),
            len(self.outline.exterior.coords),
            len(self.holes),
            tuple(sorted(round(hole.area, 3) for hole in self.holes)),
        )

    def __repr__(self) -> str:  # pragma: no cover - debug aid
        return (
            f"Part({self.part_id!r}, name={self.name!r}, qty={self.quantity}, "
            f"{self.width:.1f}x{self.height:.1f}, holes={len(self.holes)})"
        )
