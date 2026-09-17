"""Symmetry-first nesting strategy (milestone M4).

Arranges parts in mirrored or repeated tile patterns across the sheet,
prioritizing pattern regularity (repeatable sheets, operator-friendly loading)
over raw material yield. Uses :mod:`nesting.geometry.symmetry` to find
mirror-symmetric parts and mirrored pairs, then tiles them in mirrored
grid/guillotine patterns.
"""

from __future__ import annotations

from ..config import NestSettings
from ..geometry.part import Part
from .base import NestingResult, Strategy


class SymmetryFirstStrategy(Strategy):
    """Maximize pattern regularity, accepting extra waste."""

    name = "symmetry-first"

    def nest(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        raise NotImplementedError("symmetry-first nesting lands with milestone M4")
