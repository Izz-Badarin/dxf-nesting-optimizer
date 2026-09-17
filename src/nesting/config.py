"""Configuration dataclasses shared across the application.

The spacing model follows ArtCAM's proven three-value scheme:

* ``tool_diameter``      - the cutter diameter (kerf source)
* ``toolpath_clearance`` - extra material kept around each part
* ``edge_clearance``     - minimum distance between parts and the sheet edge

The minimum outline-to-outline gap between two parts is
``tool_diameter + 2 * toolpath_clearance``; half of it is charged to each part
when collision shapes are grown.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class SheetSpec:
    """A rectangular sheet. Defaults to the standard 1220 x 2440 mm board."""

    width: float = 1220.0
    height: float = 2440.0

    def __post_init__(self) -> None:
        if self.width <= 0 or self.height <= 0:
            raise ValueError("sheet dimensions must be positive")

    @property
    def area(self) -> float:
        return self.width * self.height


@dataclass(frozen=True)
class NestSettings:
    """All knobs that influence import, nesting and reporting."""

    sheet: SheetSpec = field(default_factory=SheetSpec)
    #: cutter diameter in mm (kerf source)
    tool_diameter: float = 6.0
    #: extra material kept around each part, mm
    toolpath_clearance: float = 4.0
    #: minimum part-to-sheet-edge distance, mm
    edge_clearance: float = 10.0
    #: allowed rotation increment in degrees (90 = axis-aligned only)
    rotation_step_deg: float = 90.0
    #: allow mirrored placements (disable for grain-direction-sensitive parts)
    allow_mirror: bool = True
    #: sagitta tolerance for curve flattening, mm
    curve_tolerance: float = 0.1
    #: endpoint matching tolerance when stitching open chains, mm
    chain_tolerance: float = 0.5
    #: OptiNest-style optimization effort budget, 1 (fast) .. 5 (exhaustive)
    calculation_depth: int = 2
    #: target unit for all internal geometry
    unit: str = "mm"
    #: force the source unit ("in", "mm", ...) instead of reading $INSUNITS
    unit_override: str | None = None

    def __post_init__(self) -> None:
        if self.tool_diameter < 0 or self.toolpath_clearance < 0 or self.edge_clearance < 0:
            raise ValueError("clearances must be non-negative")
        if not 0 < self.rotation_step_deg <= 180:
            raise ValueError("rotation_step_deg must be in (0, 180]")
        if not 1 <= self.calculation_depth <= 5:
            raise ValueError("calculation_depth must be in 1..5")

    @property
    def part_spacing(self) -> float:
        """Minimum gap between two part outlines on the sheet, mm."""
        return self.tool_diameter + 2.0 * self.toolpath_clearance

    @property
    def collision_grow(self) -> float:
        """Per-part outline growth used for overlap tests (half the spacing)."""
        return self.part_spacing / 2.0

    @property
    def usable_width(self) -> float:
        return self.sheet.width - 2.0 * self.edge_clearance

    @property
    def usable_height(self) -> float:
        return self.sheet.height - 2.0 * self.edge_clearance
