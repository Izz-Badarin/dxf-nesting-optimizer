"""PDF visualization of sheet layouts and the comparison summary (M5).

Renders one summary page (job, metrics table, recommendation) and one page
per unique sheet per strategy, parts colored by part id, offcuts hatched.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.backends.backend_pdf import PdfPages  # noqa: E402
from matplotlib.patches import Polygon as MplPolygon  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402

from ..nesting.base import NestingResult, SheetLayout  # noqa: E402
from ..nesting.common import merge_identical_sheets  # noqa: E402

_PALETTE = [
    "#4e79a7",
    "#f28e2b",
    "#e15759",
    "#76b7b2",
    "#59a14f",
    "#edc948",
    "#b07aa1",
    "#ff9da7",
    "#9c755f",
    "#bab0ac",
    "#d37295",
    "#9b7653",
    "#86bcb6",
    "#f1ce63",
    "#7f6f5f",
    "#b6a2e2",
    "#67c4a1",
    "#d4a6c8",
    "#8cd17d",
    "#b82e2e",
]


def part_colors(results: list[NestingResult]) -> dict[str, str]:
    """Deterministic color per part id across all results."""
    part_ids = sorted({p.part.part_id for r in results for s in r.sheets for p in s.placements})
    return {part_id: _PALETTE[i % len(_PALETTE)] for i, part_id in enumerate(part_ids)}


def export_nesting_pdf(
    results: list[NestingResult],
    path: str | Path,
    comparison: dict | None = None,
) -> Path:
    """Render nesting results to a multi-page PDF."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    colors = part_colors(results)

    with PdfPages(path) as pdf:
        if comparison is not None:
            _summary_page(pdf, comparison)
        for result in results:
            merged = merge_identical_sheets(result.sheets)
            total = len(merged)
            for sheet in merged:
                _sheet_page(pdf, result, sheet, colors, total)
    return path


def render_sheet_png(
    result: NestingResult, sheet: SheetLayout, path: str | Path, dpi: int = 150
) -> Path:
    """Render a single sheet layout as a PNG image (used in docs/README)."""
    colors = part_colors([result])
    fig = _sheet_figure(result, sheet, colors, 1)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi)
    plt.close(fig)
    return path


def _summary_page(pdf: PdfPages, comparison: dict) -> None:
    fig = plt.figure(figsize=(11.69, 8.27))
    fig.suptitle("Nesting comparison report", fontsize=16, fontweight="bold")
    job = comparison.get("job", {})
    lines = [
        f"Source: {job.get('source_file', '?')}    "
        f"DXF: {job.get('dxf_version', '?')}    Unit: {job.get('unit', '?')}",
        f"Sheet: {job.get('sheet', {}).get('width', '?')} x "
        f"{job.get('sheet', {}).get('height', '?')} mm    "
        f"Parts: {job.get('parts', {}).get('unique', '?')} unique / "
        f"{job.get('parts', {}).get('total_quantity', '?')} total",
    ]
    fig.text(0.5, 0.92, "\n".join(lines), ha="center", fontsize=10, color="#444444")

    table = comparison.get("comparison", {}).get("table", [])
    names = sorted(comparison.get("strategies", {}))
    if table and names:
        rows = [[row["metric"]] + [str(row[name]) for name in names] for row in table]
        column_width = [0.42] + [0.22] * len(names)
        ax = fig.add_axes((0.06, 0.30, 0.88, 0.55))
        ax.axis("off")
        mpl_table = ax.table(
            cellText=rows,
            colLabels=["Metric"] + names,
            colWidths=column_width,
            loc="upper center",
        )
        mpl_table.auto_set_font_size(False)
        mpl_table.set_fontsize(9)
        mpl_table.scale(1, 1.35)

    recommendation = comparison.get("comparison", {}).get("recommendation")
    if recommendation:
        text = f"Recommendation: {recommendation['strategy']}  (scores: {recommendation['scores']})"
        fig.text(0.5, 0.20, text, ha="center", fontsize=13, fontweight="bold", color="#166534")
        for i, note in enumerate(recommendation["rationale"][:5]):
            fig.text(0.5, 0.15 - i * 0.035, f"- {note}", ha="center", fontsize=10, color="#333333")
    pdf.savefig(fig)
    plt.close(fig)


def _sheet_page(
    pdf: PdfPages, result: NestingResult, sheet: SheetLayout, colors: dict, total: int
) -> None:
    fig = _sheet_figure(result, sheet, colors, total)
    pdf.savefig(fig)
    plt.close(fig)


def _sheet_figure(result: NestingResult, sheet: SheetLayout, colors: dict, total: int):
    settings = result.settings
    width = settings.sheet.width
    height = settings.sheet.height
    portrait = height >= width
    figsize = (8.27, 11.69) if portrait else (11.69, 8.27)
    fig = plt.figure(figsize=figsize)

    title = f"{result.strategy} - sheet {sheet.index}/{total}"
    if sheet.copies > 1:
        title += f" (x{sheet.copies} copies - machine once, repeat)"
    used = sum(p.part.area for p in sheet.placements)
    utilization = 100.0 * used / settings.sheet.area
    fig.suptitle(f"{title}\nsheet utilization {utilization:.1f}%", fontsize=12)

    ax = fig.add_axes((0.04, 0.03, 0.92, 0.90))
    ax.add_patch(Rectangle((0, 0), width, height, fill=False, edgecolor="#111111", lw=1.5))
    for offcut in sheet.offcuts:
        ax.add_patch(
            MplPolygon(
                list(offcut.exterior.coords),
                closed=True,
                facecolor="#f2f2f2",
                edgecolor="#999999",
                hatch="///",
                lw=0.4,
            )
        )
    for placement in sheet.placements:
        polygon = placement.polygon
        color = colors.get(placement.part.part_id, "#cccccc")
        ax.add_patch(
            MplPolygon(
                list(polygon.exterior.coords),
                closed=True,
                facecolor=color,
                edgecolor="#1e293b",
                lw=0.5,
                alpha=0.9,
            )
        )
        for hole in placement.hole_polygons:
            ax.add_patch(
                MplPolygon(
                    list(hole.exterior.coords),
                    closed=True,
                    facecolor="white",
                    edgecolor="#1e293b",
                    lw=0.5,
                )
            )
        label_point = polygon.representative_point()
        size = min(placement.part.width, placement.part.height)
        if size >= 120:
            ax.text(
                label_point.x,
                label_point.y,
                placement.part.part_id,
                ha="center",
                va="center",
                fontsize=5,
                color="#111111",
            )
    ax.set_xlim(-width * 0.03, width * 1.03)
    ax.set_ylim(-height * 0.03, height * 1.03)
    ax.set_aspect("equal")
    ax.axis("off")
    return fig
