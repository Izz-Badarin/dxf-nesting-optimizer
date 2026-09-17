"""Deterministically generate the example DXF inputs.

Usage:
    python examples/generate.py [--out examples/inputs]

Files:
    furniture_parts.dxf   cabinet job: block-based side panels, shelves,
                          rounded-top doors, drawer fronts, kick plates
    mixed_curved.dxf      rings, line/arc chains, ellipses, a spline blob,
                          a gear with holes, a mirrored pair
    stress_many_parts.dxf 400 mixed parts for performance testing
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

import ezdxf


def new_doc() -> ezdxf.document.Drawing:
    doc = ezdxf.new("R2018")
    doc.header["$INSUNITS"] = 4  # millimeters
    return doc


def rect(msp, x: float, y: float, w: float, h: float, layer: str = "0") -> None:
    msp.add_lwpolyline(
        [(x, y, 0, 0, 0), (x + w, y, 0, 0, 0), (x + w, y + h, 0, 0, 0), (x, y + h, 0, 0, 0)],
        close=True,
        dxfattribs={"layer": layer},
    )


def label(msp, text: str, x: float, y: float, layer: str = "0", height: float = 20.0) -> None:
    msp.add_text(text, dxfattribs={"layer": layer, "height": height}).set_placement((x, y))


def rounded_rect(msp, x: float, y: float, w: float, h: float, r: float, layer: str) -> None:
    """Closed polyline with quarter-circle (bulge = tan(45deg/2)) corners."""
    b = math.tan(math.pi / 8)  # 0.4142...
    pts = [
        (x, y + r, 0, 0, 0),
        (x, y + h - r, 0, 0, b),
        (x + r, y + h, 0, 0, 0),
        (x + w - r, y + h, 0, 0, b),
        (x + w, y + h - r, 0, 0, 0),
        (x + w, y + r, 0, 0, b),
        (x + w - r, y, 0, 0, 0),
        (x + r, y, 0, 0, b),
    ]
    msp.add_lwpolyline(pts, close=True, dxfattribs={"layer": layer})


def furniture(path: Path) -> None:
    doc = new_doc()
    for name, color in (("PANEL", 7), ("SHELF", 3), ("DOOR", 5), ("DRAWER", 4), ("KICK", 8)):
        doc.layers.add(name, color=color)
    msp = doc.modelspace()

    # Side panels: a block (rect + 4 system holes + text), inserted 4 times.
    blk = doc.blocks.new("SIDE_PANEL")
    blk.add_lwpolyline(
        [(0, 0, 0, 0, 0), (600, 0, 0, 0, 0), (600, 800, 0, 0, 0), (0, 800, 0, 0, 0)],
        close=True,
    )
    for hx, hy in ((50, 50), (550, 50), (50, 750), (550, 750)):
        blk.add_circle((hx, hy), 2.5)
    blk.add_text("SIDE 600x800", dxfattribs={"height": 30}).set_placement((60, 400))

    msp.add_blockref("SIDE_PANEL", (0, 0), dxfattribs={"layer": "PANEL"})
    msp.add_blockref("SIDE_PANEL", (700, 0), dxfattribs={"layer": "PANEL"})
    msp.add_blockref("SIDE_PANEL", (1400, 0), dxfattribs={"layer": "PANEL"})
    msp.add_blockref("SIDE_PANEL", (0, 1200), dxfattribs={"layer": "PANEL", "rotation": 90})

    # Shelves: 6 identical loose rectangles on SHELF.
    for i in range(6):
        x = 2200 + (i % 3) * 700
        y = 0 + (i // 3) * 700
        rect(msp, x, y, 580, 500, "SHELF")
    label(msp, "SHELF-580", 2250, 200, "SHELF")

    # Doors: rounded top (bulge = 1 -> semicircle), 2 identical.
    msp.add_lwpolyline(
        [
            (2200, 1500, 0, 0, 0),
            (2600, 1500, 0, 0, 0),
            (2600, 1800, 0, 0, 1),
            (2200, 1800, 0, 0, 0),
        ],
        close=True,
        dxfattribs={"layer": "DOOR"},
    )
    msp.add_lwpolyline(
        [
            (2700, 1500, 0, 0, 0),
            (3100, 1500, 0, 0, 0),
            (3100, 1800, 0, 0, 1),
            (2700, 1800, 0, 0, 0),
        ],
        close=True,
        dxfattribs={"layer": "DOOR"},
    )
    label(msp, "DOOR-400", 2300, 1650, "DOOR")
    label(msp, "DOOR-400", 2800, 1650, "DOOR")

    # Drawer fronts: 4 identical.
    for i in range(4):
        rect(msp, 2200 + i * 500, 2200, 397, 297, "DRAWER")
    label(msp, "DRAWER", 2250, 2300, "DRAWER")

    # Kick plates: 2 identical.
    rect(msp, 4400, 0, 100, 800, "KICK")
    rect(msp, 4600, 0, 100, 800, "KICK")

    doc.saveas(path)


def mixed_curved(path: Path) -> None:
    doc = new_doc()
    for name, color in (("RING", 7), ("BRACKET", 3), ("CURVED", 5), ("GEAR", 4), ("MIRROR", 8)):
        doc.layers.add(name, color=color)
    msp = doc.modelspace()

    # Two identical rings (annulus: circle inside circle -> hole).
    for cx in (0.0, 600.0):
        msp.add_circle((cx, 200), 200, dxfattribs={"layer": "RING"})
        msp.add_circle((cx, 200), 120, dxfattribs={"layer": "RING"})

    # L-bracket: 6 loose LINE entities forming a closed L (chain stitching).
    ox, oy = 1000.0, 0.0
    corners = [(0, 0), (300, 0), (300, 40), (40, 40), (40, 300), (0, 300)]
    pts = [(ox + x, oy + y) for x, y in corners]
    for a, b in zip(pts, pts[1:] + pts[:1], strict=True):
        msp.add_line(a, b, dxfattribs={"layer": "BRACKET"})

    # Capsule: 2 lines + 2 arcs (chain stitching with curves).
    msp.add_line((1600, 0), (1900, 0), dxfattribs={"layer": "BRACKET"})
    msp.add_arc((1900, 100), 100, -90, 90, dxfattribs={"layer": "BRACKET"})
    msp.add_line((1900, 200), (1600, 200), dxfattribs={"layer": "BRACKET"})
    msp.add_arc((1600, 100), 100, 90, 270, dxfattribs={"layer": "BRACKET"})

    # Two identical ellipses.
    msp.add_ellipse(
        (2500, 100), major_axis=(150, 0), ratio=80.0 / 150.0, dxfattribs={"layer": "CURVED"}
    )
    msp.add_ellipse(
        (2900, 100), major_axis=(150, 0), ratio=80.0 / 150.0, dxfattribs={"layer": "CURVED"}
    )

    # Spline blob.
    msp.add_spline(
        fit_points=[(3400, 0), (3450, 120), (3560, 160), (3640, 80), (3580, 0)],
        dxfattribs={"layer": "CURVED"},
    ).closed = True

    # Gear: circle with 6 holes.
    gx, gy = 4000.0, 200.0
    msp.add_circle((gx, gy), 150, dxfattribs={"layer": "GEAR"})
    for k in range(6):
        angle = math.radians(60 * k)
        msp.add_circle(
            (gx + 100 * math.cos(angle), gy + 100 * math.sin(angle)),
            20,
            dxfattribs={"layer": "GEAR"},
        )

    # Mirrored pair: asymmetric quad + its x-mirror.
    quad = [(0, 0), (200, 0), (260, 120), (60, 180)]
    msp.add_lwpolyline(
        [(4500 + x, y, 0, 0, 0) for x, y in quad], close=True, dxfattribs={"layer": "MIRROR"}
    )
    msp.add_lwpolyline(
        [(5000 - x, y, 0, 0, 0) for x, y in quad], close=True, dxfattribs={"layer": "MIRROR"}
    )

    doc.saveas(path)


def batch(path: Path) -> None:
    """A repeating production batch: many copies of few part types."""
    doc = new_doc()
    for name, color in (("BRACKET", 3), ("PANEL", 7), ("RING", 5)):
        doc.layers.add(name, color=color)
    msp = doc.modelspace()

    # 40 L-brackets (loose lines, chain-stitched on import)
    for i in range(40):
        ox, oy = (i % 8) * 500.0, (i // 8) * 500.0
        corners = [(0, 0), (300, 0), (300, 40), (40, 40), (40, 300), (0, 300)]
        pts = [(ox + x, oy + y) for x, y in corners]
        for a, b in zip(pts, pts[1:] + pts[:1], strict=True):
            msp.add_line(a, b, dxfattribs={"layer": "BRACKET"})

    # 24 panels with a handle hole
    for i in range(24):
        x, y = 4500 + (i % 6) * 500.0, (i // 6) * 400.0
        msp.add_lwpolyline(
            [
                (x, y, 0, 0, 0),
                (x + 400, y, 0, 0, 0),
                (x + 400, y + 300, 0, 0, 0),
                (x, y + 300, 0, 0, 0),
            ],
            close=True,
            dxfattribs={"layer": "PANEL"},
        )
        msp.add_circle((x + 200, y + 250), 30, dxfattribs={"layer": "PANEL"})

    # 12 rings
    for i in range(12):
        cx = 4500 + (i % 6) * 500.0
        cy = 2000 + (i // 6) * 500.0
        msp.add_circle((cx, cy), 150, dxfattribs={"layer": "RING"})
        msp.add_circle((cx, cy), 90, dxfattribs={"layer": "RING"})

    doc.saveas(path)


def stress(path: Path) -> None:
    doc = new_doc()
    doc.layers.add("PARTS", color=7)
    msp = doc.modelspace()
    rng = random.Random(7)

    def slot(i: int) -> tuple[float, float]:
        return (i % 40) * 900.0, (i // 40) * 900.0

    for i in range(250):  # rectangles
        x, y = slot(i)
        rect(msp, x, y, rng.uniform(80, 500), rng.uniform(80, 700), "PARTS")
    for i in range(100):  # circles
        x, y = slot(250 + i)
        msp.add_circle((x + 300, y + 300), rng.uniform(30, 120), dxfattribs={"layer": "PARTS"})
    for i in range(50):  # rounded rectangles
        x, y = slot(350 + i)
        rounded_rect(msp, x, y, rng.uniform(150, 400), rng.uniform(150, 400), 30.0, "PARTS")

    doc.saveas(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "inputs")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    furniture(args.out / "furniture_parts.dxf")
    mixed_curved(args.out / "mixed_curved.dxf")
    batch(args.out / "repeating_batch.dxf")
    stress(args.out / "stress_many_parts.dxf")
    print(f"generated 4 DXF files in {args.out}")


if __name__ == "__main__":
    main()
