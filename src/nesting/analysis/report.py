"""Report writers: JSON (machine) and Markdown (human) - milestone M5.

The report schema is specified in ``docs/report-schema.md``.
"""

from __future__ import annotations

from pathlib import Path


def write_json_report(data: dict[str, object], path: str | Path) -> Path:
    raise NotImplementedError("JSON report lands with milestone M5")


def write_markdown_report(data: dict[str, object], path: str | Path) -> Path:
    raise NotImplementedError("Markdown report lands with milestone M5")
