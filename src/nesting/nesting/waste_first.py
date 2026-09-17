"""Waste-minimization nesting strategy (milestone M3).

Arranges parts purely to minimize unused sheet area, regardless of symmetry.
v0.1 plan: rotation-step-limited true-polygon placement with MaxRects, shelf
and bottom-left heuristics (best-of-N), multi-sheet support, deterministic
ordering. Free rotation + NFP + simulated-annealing refinement arrive in the
phase-2 optimizer.
"""

from __future__ import annotations

from ..config import NestSettings
from ..geometry.part import Part
from .base import NestingResult, Strategy


class WasteFirstStrategy(Strategy):
    """Minimize unused sheet area."""

    name = "waste-first"

    def nest(self, parts: list[Part], settings: NestSettings) -> NestingResult:
        raise NotImplementedError("waste-first nesting lands with milestone M3")
