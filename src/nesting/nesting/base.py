"""Core nesting abstractions: strategies, placements, sheet layouts, results."""

from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from shapely.geometry import Polygon

from ..config import NestSettings
from ..geometry.part import Part


@dataclass
class Placement:
    """One part placed on one sheet.

    Semantics: the part outline (normalized to origin at import) is mirrored
    about x=0, rotated CCW about the origin by ``rotation_deg``, then
    translated to (x, y) on the sheet.
    """

    part: Part
    sheet_index: int
    x: float
    y: float
    rotation_deg: float = 0.0
    mirrored: bool = False

    @property
    def polygon(self) -> Polygon:
        return self.part.geometry(self.x, self.y, self.rotation_deg, self.mirrored)

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        return self.polygon.bounds


@dataclass
class SheetLayout:
    """One sheet of a nesting result.

    ``copies`` implements ArtCAM-style identical-sheet merging: when several
    sheets carry exactly the same layout, they are reported once with a copy
    count ("Sheet 1 (3 copies)" - machine once, repeat).
    """

    index: int
    placements: list[Placement] = field(default_factory=list)
    copies: int = 1
    #: remaining usable regions (leftover material) as polygons
    offcuts: list[Polygon] = field(default_factory=list)

    @property
    def used_area(self) -> float:
        return sum(placement.part.area for placement in self.placements)


@dataclass
class NestingResult:
    """The output of one strategy run."""

    strategy: str
    settings: NestSettings
    sheets: list[SheetLayout] = field(default_factory=list)
    unplaced: list[Part] = field(default_factory=list)
    runtime_s: float = 0.0

    @property
    def total_part_area(self) -> float:
        return sum(sheet.used_area for sheet in self.sheets)

    @property
    def total_placements(self) -> int:
        return sum(len(sheet.placements) for sheet in self.sheets)


class Strategy(ABC):
    """A nesting strategy turns a validated part list into a NestingResult."""

    name: str = "base"

    @abstractmethod
    def nest(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        """Produce placements for all parts (or report them as unplaced)."""

    def timed_nest(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        start = time.perf_counter()
        result = self.nest(parts, settings)
        result.runtime_s = time.perf_counter() - start
        return result
