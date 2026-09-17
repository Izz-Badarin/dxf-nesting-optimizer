"""DXF export of nesting results (milestone M3).

Will write one CNC-ready DXF per strategy with the sheet outline on layer
``CNC_BOUNDARY``, parts on ``CUT`` and part labels on ``ETCH``. Axis-aligned
placements preserve arcs; rotated placements are emitted as fine polylines.
Offcuts (leftover material) are exported as closed polylines on ``OFFCUT``.
"""

from __future__ import annotations

from pathlib import Path

from ..nesting.base import NestingResult


def export_nesting_dxf(result: NestingResult, path: str | Path) -> Path:
    """Export a nesting result to a CNC-ready DXF file."""
    raise NotImplementedError("DXF export lands with milestone M3")
