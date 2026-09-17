"""Metric computations for the comparative analysis.

Area metrics and sheet-replication are available now (they only need
placements); CNC handling factors land with milestone M5. Full definitions
are documented in ``docs/metrics.md``.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Sequence
from hashlib import sha256
from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover - import for typing only
    from ..nesting.base import Placement, SheetLayout


def utilization_pct(total_part_area: float, sheet_count: int, sheet_area: float) -> float:
    """Net material utilization: true part area over total sheet area, percent."""
    if sheet_count <= 0 or sheet_area <= 0:
        return 0.0
    return 100.0 * total_part_area / (sheet_count * sheet_area)


def waste_pct(total_part_area: float, sheet_count: int, sheet_area: float) -> float:
    """Net waste percentage (100 - utilization), floored at zero."""
    return max(0.0, 100.0 - utilization_pct(total_part_area, sheet_count, sheet_area))


def sheet_signature(placements: Sequence[Placement]) -> str:
    """Stable signature of a sheet layout.

    Two sheets with the same signature are identical layouts (ArtCAM-style
    "Sheet 1 (3 copies)" merging). Position, rotation and mirror are rounded
    to 0.001 mm / degree so floating-point noise never splits identical sheets.
    """
    items = sorted(
        (
            placement.part.part_id,
            round(placement.x, 3),
            round(placement.y, 3),
            round(placement.rotation_deg, 3),
            placement.mirrored,
        )
        for placement in placements
    )
    return sha256(repr(items).encode("utf-8")).hexdigest()[:16]


def replication_efficiency(sheet_signatures: Sequence[str]) -> float:
    """Sheet replication efficiency in [0, 1].

    ``sum(group_size - 1) / (sheet_count - 1)`` over signature groups: 1.0
    means every sheet is an exact repeat of the first (machine once, repeat N
    times); a single-sheet job is trivially repeatable (1.0).
    """
    count = len(sheet_signatures)
    if count <= 1:
        return 1.0
    groups = Counter(sheet_signatures)
    return sum(size - 1 for size in groups.values()) / (count - 1)


def sheet_copy_counts(sheets: Sequence[SheetLayout]) -> list[int]:
    """Copy count per unique layout, in first-appearance order."""
    seen: dict[str, int] = {}
    for sheet in sheets:
        signature = sheet_signature(sheet.placements)
        seen[signature] = seen.get(signature, 0) + sheet.copies
    return list(seen.values())
