"""Smoke tests: the committed example DXFs must import cleanly."""

from __future__ import annotations

from pathlib import Path

import pytest

from nesting import import_dxf

INPUTS = Path(__file__).parents[1] / "examples" / "inputs"

CASES = [
    ("furniture_parts.dxf", 5, 18, 0),
    ("mixed_curved.dxf", 6, 10, 0),
    ("stress_many_parts.dxf", 100, 300, 0),
]


@pytest.mark.parametrize(("name", "min_unique", "min_quantity", "max_warnings"), CASES)
def test_example_imports(name: str, min_unique: int, min_quantity: int, max_warnings: int):
    result = import_dxf(INPUTS / name)
    assert len(result.parts) >= min_unique, f"{name}: {len(result.parts)} unique parts"
    assert result.total_quantity >= min_quantity, f"{name}: {result.total_quantity} total"
    assert len(result.warnings) <= max_warnings, f"{name}: {result.warnings}"
    assert result.source_unit in ("millimeters", "unitless")


def test_furniture_job_shape():
    result = import_dxf(INPUTS / "furniture_parts.dxf")
    by_name = {part.name: part for part in result.parts}
    side = by_name["SIDE_PANEL"]
    assert side.quantity == 4
    assert len(side.holes) == 4
    assert side.width == pytest.approx(600)
    assert side.height == pytest.approx(800)
    assert "SIDE 600x800" in side.text_meta

    shelf = by_name["SHELF"]
    assert shelf.quantity == 6
    assert shelf.area == pytest.approx(580 * 500)

    door = by_name["DOOR"]
    assert door.quantity == 2
    assert door.area == pytest.approx(400 * 300 + 3.14159 * 200**2 / 2, rel=1e-3)

    assert by_name["DRAWER"].quantity == 4
    assert by_name["KICK"].quantity == 2


def test_mixed_curved_job_shape():
    result = import_dxf(INPUTS / "mixed_curved.dxf")
    by_layer = {}
    for part in result.parts:
        by_layer.setdefault(part.layer, []).append(part)

    ring = by_layer["RING"][0]
    assert len(ring.holes) == 1
    assert ring.quantity == 2

    gear = by_layer["GEAR"][0]
    assert len(gear.holes) == 6

    brackets = by_layer["BRACKET"]
    assert len(brackets) == 2  # L-bracket and capsule
    # L-bracket: 300x300 outer minus 260x260 notch
    l_bracket = min(brackets, key=lambda p: p.area)
    assert l_bracket.area == pytest.approx(300 * 300 - 260 * 260, rel=1e-3)
