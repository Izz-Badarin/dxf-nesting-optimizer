"""Command line interface.

dxfnest info <file.dxf> [--unit UNIT] [--json]
dxfnest nest <file.dxf> [options]      # dual nesting + exports + reports
dxfnest gui [--host H] [--port P]      # web GUI
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from ._version import __version__
from .analysis.compare import build_report
from .analysis.report import write_json_report, write_markdown_report
from .config import NestSettings, SheetSpec
from .io.dxf_export import export_nesting_dxf
from .io.dxf_import import UNIT_ALIASES, import_dxf
from .io.pdf_report import export_nesting_pdf
from .nesting.base import Strategy
from .nesting.symmetry_first import SymmetryFirstStrategy
from .nesting.waste_first import WasteFirstStrategy

STRATEGIES: dict[str, type[Strategy]] = {
    "symmetry-first": SymmetryFirstStrategy,
    "waste-first": WasteFirstStrategy,
}


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

    nest = sub.add_parser("nest", help="nest parts and export layouts")
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
    nest.add_argument("--depth", type=int, default=2, choices=(1, 2, 3, 4, 5))
    nest.add_argument("--pdf", action="store_true", help="also render a PDF visualization")
    nest.add_argument("--report", choices=("json", "md", "both"), default="both")

    gui = sub.add_parser("gui", help="launch the web GUI")
    gui.add_argument("--host", default="127.0.0.1")
    gui.add_argument("--port", type=int, default=8000)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "info":
        return _cmd_info(args)
    if args.command == "nest":
        return _cmd_nest(args)
    if args.command == "gui":
        return _cmd_gui(args)
    return 2


# -- info --------------------------------------------------------------------


def _cmd_info(args: argparse.Namespace) -> int:
    result = import_dxf(args.dxf, NestSettings(unit_override=args.unit))

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


# -- nest --------------------------------------------------------------------


def _parse_sheet(spec: str) -> SheetSpec:
    try:
        width, _, height = spec.lower().partition("x")
        return SheetSpec(width=float(width), height=float(height))
    except ValueError as exc:
        raise SystemExit(f"error: invalid --sheet '{spec}' (expected e.g. 1220x2440)") from exc


def _settings_from_args(args: argparse.Namespace) -> NestSettings:
    return NestSettings(
        sheet=_parse_sheet(args.sheet),
        tool_diameter=args.tool_diameter,
        toolpath_clearance=args.clearance,
        edge_clearance=args.edge_clearance,
        rotation_step_deg=args.rotation_step,
        allow_mirror=args.allow_mirror,
        calculation_depth=args.depth,
    )


def _cmd_nest(args: argparse.Namespace) -> int:
    settings = _settings_from_args(args)
    imported = import_dxf(args.dxf, settings)
    if not imported.parts:
        print("error: no nestable parts found in the DXF file", file=sys.stderr)
        return 1
    if imported.warnings:
        for warning in imported.warnings:
            print(f"warning: {warning}", file=sys.stderr)

    total_area = sum(p.area * p.quantity for p in imported.parts)
    print(
        f"Imported : {len(imported.parts)} unique parts / {imported.total_quantity} total"
        f" ({total_area:,.0f} mm2)"
    )
    print(
        f"Sheet    : {settings.sheet.width:.0f} x {settings.sheet.height:.0f} mm,"
        f" spacing {settings.part_spacing:.1f} mm, edge {settings.edge_clearance:.0f} mm"
    )
    print()

    wanted: list[str]
    if args.strategy == "both":
        wanted = ["symmetry-first", "waste-first"]
    elif args.strategy == "symmetry":
        wanted = ["symmetry-first"]
    else:
        wanted = ["waste-first"]

    args.outdir.mkdir(parents=True, exist_ok=True)
    stem = args.dxf.stem

    results = {}
    for name in wanted:
        strategy = STRATEGIES[name]()
        result = strategy.timed_nest(imported.parts, settings)
        results[name] = result
        out_dxf = export_nesting_dxf(result, args.outdir / f"{stem}_{name}.dxf", args.dxf.name)
        placed = result.total_placements
        unplaced = sum(p.quantity for p in result.unplaced)
        print(
            f"{name:<16} sheets={len(result.sheets)}  placed={placed}"
            f"  unplaced={unplaced}  runtime={result.runtime_s:.2f}s"
        )
        print(f"{'':<16} -> {out_dxf}")
    print()

    job = {
        "source_file": str(args.dxf),
        "dxf_version": imported.stats.get("dxf_version"),
        "unit": imported.source_unit,
        "sheet": {"width": settings.sheet.width, "height": settings.sheet.height},
        "settings": asdict(settings),
        "parts": {
            "unique": len(imported.parts),
            "total_quantity": imported.total_quantity,
            "total_area_mm2": round(total_area, 3),
        },
    }
    report = build_report(job, results)

    written = []
    if args.report in ("json", "both"):
        written.append(write_json_report(report, args.outdir / "comparison_report.json"))
    if args.report in ("md", "both"):
        written.append(write_markdown_report(report, args.outdir / "comparison_report.md"))
    if args.pdf:
        written.append(
            export_nesting_pdf(
                [results[name] for name in wanted],
                args.outdir / f"{stem}_comparison.pdf",
                comparison=report,
            )
        )

    _print_summary(report, written)

    any_unplaced = any(result.unplaced for result in results.values())
    if any_unplaced:
        print("\nwarning: some parts did not fit - see the report for details", file=sys.stderr)
        return 1
    return 0


def _print_summary(report: dict, written: list[Path]) -> None:
    names = sorted(report["strategies"])
    print(f"{'Metric':<28}" + "".join(f"{n:>18}" for n in names))
    for row in report["comparison"]["table"]:
        label = row["metric"]
        cells = "".join(f"{str(row[n]):>18}" for n in names)
        print(f"{label:<28}{cells}")
    recommendation = report["comparison"].get("recommendation")
    if recommendation:
        print()
        print(f"Recommendation: {recommendation['strategy']}")
        for note in recommendation["rationale"]:
            print(f"  - {note}")
    if written:
        print()
        print("Outputs:")
        for path in written:
            print(f"  - {path}")


# -- gui ---------------------------------------------------------------------


def _cmd_gui(args: argparse.Namespace) -> int:
    try:
        import uvicorn
    except ImportError:
        print(
            "error: GUI dependencies are missing - install them with:\n"
            "    pip install 'dxf-nesting-optimizer[gui]'",
            file=sys.stderr,
        )
        return 2
    from .gui.app import app

    print(f"dxfnest GUI -> http://{args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
