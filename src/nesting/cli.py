"""Command line interface.

dxfnest info <file.dxf> [--unit UNIT] [--json]
dxfnest nest <file.dxf> ...                    (milestone M3+)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__
from .config import NestSettings
from .io.dxf_import import UNIT_ALIASES, import_dxf


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="dxfnest",
        description="Dual-strategy DXF nesting optimizer with comparative analysis.",
    )
    parser.add_argument("--version", action="version", version=f"dxfnest {__version__}")

    sub = parser.add_subparsers(dest="command", required=True)

    info = sub.add_parser("info", help="inspect a DXF file: parts, quantities, warnings")
    info.add_argument("dxf", type=Path, help="path to the input DXF file")
    info.add_argument(
        "--unit",
        choices=sorted(UNIT_ALIASES),
        default=None,
        help="override the source unit (default: read $INSUNITS)",
    )
    info.add_argument("--json", action="store_true", help="emit machine-readable JSON")

    nest = sub.add_parser("nest", help="nest parts and export layouts (milestone M3+)")
    nest.add_argument("dxf", type=Path)
    nest.add_argument("-o", "--outdir", type=Path, default=Path("nesting-output"))
    nest.add_argument("--strategy", choices=("symmetry", "waste", "both"), default="both")
    nest.add_argument("--sheet", default="1220x2440", help="sheet size in mm, e.g. 1220x2440")
    nest.add_argument("--tool-diameter", type=float, default=6.0)
    nest.add_argument("--clearance", type=float, default=4.0)
    nest.add_argument("--edge-clearance", type=float, default=10.0)
    nest.add_argument("--rotation-step", type=float, default=90.0)
    nest.add_argument("--mirror", dest="allow_mirror", action="store_true", default=True)
    nest.add_argument("--no-mirror", dest="allow_mirror", action="store_false")
    nest.add_argument("--pdf", action="store_true", help="also render a PDF visualization")
    nest.add_argument("--report", choices=("json", "md", "both"), default="both")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "info":
        return _cmd_info(args)
    if args.command == "nest":
        print(
            "error: 'nest' is not implemented yet - it lands with milestone M3 "
            "(waste-first engine + DXF export). 'info' is fully functional.",
            file=sys.stderr,
        )
        return 2
    return 2


def _cmd_info(args: argparse.Namespace) -> int:
    settings = NestSettings(unit_override=args.unit)
    result = import_dxf(args.dxf, settings)

    if args.json:
        print(json.dumps(result.to_dict(), indent=2))
        return 0 if result.parts else 1

    print(f"DXF       : {args.dxf}")
    print(f"Version   : {result.stats.get('dxf_version', '?')}")
    print(f"Unit      : {result.source_unit} (x{result.scale_to_mm:g} to mm)")
    print(f"Parts     : {len(result.parts)} unique / {result.total_quantity} total")
    print()
    header = (
        f"{'ID':<6}{'Name':<22}{'Layer':<12}{'Qty':>4}"
        f"  {'W x H (mm)':<14}{'Area (mm2)':>14}  {'Holes':>5}"
    )
    print(header)
    print("-" * 82)
    for part in sorted(result.parts, key=lambda p: p.part_id):
        size = f"{part.width:.0f} x {part.height:.0f}"
        print(
            f"{part.part_id:<6}{part.name[:21]:<22}{part.layer[:11]:<12}{part.quantity:>4}"
            f"  {size:<14}{part.area:>14,.0f}  {len(part.holes):>5}"
        )
    if result.warnings:
        print(f"\nWarnings ({len(result.warnings)}):")
        for warning in result.warnings:
            print(f"  - {warning}")
    if not result.parts:
        print("\nno nestable parts found", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
