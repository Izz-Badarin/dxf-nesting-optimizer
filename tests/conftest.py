"""Shared test fixtures."""

from __future__ import annotations

from collections.abc import Callable

import ezdxf
import pytest


@pytest.fixture
def make_dxf(tmp_path):
    """Factory fixture: build a DXF file from an entity-building callback."""

    def _make(
        build: Callable[[object, object], None],
        name: str = "test.dxf",
        insunits: int = 4,
    ) -> object:
        doc = ezdxf.new("R2018")
        doc.header["$INSUNITS"] = insunits
        msp = doc.modelspace()
        build(msp, doc)
        path = tmp_path / name
        doc.saveas(path)
        return path

    return _make
