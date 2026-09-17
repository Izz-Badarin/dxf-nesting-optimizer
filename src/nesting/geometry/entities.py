"""Lightweight geometric entity records.

The nesting engine works on tessellated Shapely polygons; these records keep
just enough source information to (a) rebuild geometry and (b) re-emit DXF
entities on export with arcs preserved for axis-aligned transforms (M3).
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Pt:
    """A 2D point in millimetres."""

    x: float
    y: float


@dataclass(frozen=True)
class Line:
    start: Pt
    end: Pt


@dataclass(frozen=True)
class Arc:
    """A circular arc, angles in degrees CCW from +x."""

    center: Pt
    radius: float
    start_angle: float
    end_angle: float


@dataclass(frozen=True)
class Circle:
    center: Pt
    radius: float


@dataclass(frozen=True)
class Polyline:
    points: tuple[Pt, ...]
    closed: bool


Entity = Line | Arc | Circle | Polyline
