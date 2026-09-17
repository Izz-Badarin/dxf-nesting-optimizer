"""DXF export of nesting results (milestone M3).

Writes one CNC-ready DXF per strategy with the sheets side by side:

* layer ``CNC_BOUNDARY`` - sheet outlines
* layer ``CUT`` - part outlines and holes (the toolpaths)
* layer ``ETCH`` - part labels (part id + quantity info)
* layer ``OFFCUT`` - reusable leftover material as closed polylines
* layer ``INFO`` - sheet titles and copy counts

Identical sheets are merged ArtCAM-style: drawn once, annotated with the
copy count ("x3 copies - machine once, repeat"). All geometry is emitted as
polylines tessellated at the configured curve tolerance; arc-preserving
export for axis-aligned transforms is planned for a later release.
"""

from __future__ import annotations

from pathlib import Path

import ezdxf
from ezdxf.enums import TextEntityAlignment
from shapely.affinity import translate as shp_translate

from ..nesting.base import NestingResult
from ..nesting.common import merge_identical_sheets, placement_holes

#: horizontal gap between side-by-side sheets in the output DXF, mm
GAP_BETWEEN_SHEETS = 100.0

_LAYERS: dict[str, int] = {
    "CNC_BOUNDARY": 1,  # red
    "CUT": 7,  # white
    "ETCH": 2,  # yellow
    "OFFCUT": 4,  # cyan
    "INFO": 8,  # dark grey
}


def export_nesting_dxf(result: NestingResult, path: str | Path, source_name: str = "") -> Path:
    """Export a nesting result to a CNC-ready DXF file."""
    path = Path(path)
    doc = ezdxf.new("R2018")
    doc.header["$INSUNITS"] = 4  # millimeters
    for name, color in _LAYERS.items():
        doc.layers.add(name, color=color)
    msp = doc.modelspace()

    width = result.settings.sheet.width
    height = result.settings.sheet.height
    merged = merge_identical_sheets(result.sheets)

    x0 = 0.0
    for sheet in merged:
        _draw_sheet(msp, result, sheet, x0, width, height)
        title = f"{result.strategy.upper()} - SHEET {sheet.index}"
        if sheet.copies > 1:
            title += f" (x{sheet.copies} copies - machine once, repeat)"
        if source_name:
            title += f" - {source_name}"
        msp.add_text(title, dxfattribs={"layer": "INFO", "height": 25.0}).set_placement(
            (x0, height + 40.0), align=TextEntityAlignment.LEFT
        )
        x0 += width + GAP_BETWEEN_SHEETS

    path.parent.mkdir(parents=True, exist_ok=True)
    doc.saveas(path)
    return path


def _draw_sheet(msp, result: NestingResult, sheet, x0: float, width: float, height: float) -> None:
    msp.add_lwpolyline(
        [
            (x0, 0.0, 0, 0, 0),
            (x0 + width, 0.0, 0, 0, 0),
            (x0 + width, height, 0, 0, 0),
            (x0, height, 0, 0, 0),
        ],
        close=True,
        dxfattribs={"layer": "CNC_BOUNDARY"},
    )
    for placement in sheet.placements:
        outline = shp_translate(placement.polygon, x0, 0.0)
        _add_ring(msp, outline, "CUT")
        for hole in placement_holes(placement):
            _add_ring(msp, shp_translate(hole, x0, 0.0), "CUT")
        label_point = outline.representative_point()
        part = placement.part
        size = min(part.width, part.height)
        height_text = max(6.0, min(24.0, size * 0.12))
        msp.add_text(
            part.part_id, dxfattribs={"layer": "ETCH", "height": height_text}
        ).set_placement((label_point.x, label_point.y), align=TextEntityAlignment.MIDDLE_CENTER)
    for offcut in sheet.offcuts:
        _add_ring(msp, shp_translate(offcut, x0, 0.0), "OFFCUT")
        for interior in offcut.interiors:
            _add_ring_coords(msp, list(interior.coords), "OFFCUT")


def _add_ring(msp, polygon, layer: str) -> None:
    _add_ring_coords(msp, list(polygon.exterior.coords), layer)
    for interior in polygon.interiors:
        _add_ring_coords(msp, list(interior.coords), layer)


def _add_ring_coords(msp, coords, layer: str) -> None:
    points = [(round(x, 4), round(y, 4), 0, 0, 0) for x, y in coords]
    if len(points) < 3:
        return
    msp.add_lwpolyline(points, close=True, dxfattribs={"layer": layer})
