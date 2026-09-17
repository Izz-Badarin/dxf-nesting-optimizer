"""PDF visualization of sheet layouts (milestone M5).

Renders every sheet of both strategies side by side with metrics tables via
Matplotlib ``PdfPages``.
"""

from __future__ import annotations

from pathlib import Path

from ..nesting.base import NestingResult


def export_nesting_pdf(results: list[NestingResult], path: str | Path) -> Path:
    """Render nesting results to a multi-page PDF."""
    raise NotImplementedError("PDF rendering lands with milestone M5")
