"""Side-by-side comparison of nesting strategies (milestone M5).

Builds the full report structure: job summary, per-strategy metrics and
sheets, the comparison table and a weighted recommendation. The same dict
feeds the JSON/Markdown writers and the web GUI.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from .._version import __version__
from .metrics import compute_metrics

if TYPE_CHECKING:  # pragma: no cover - import for typing only
    from ..nesting.base import NestingResult

#: default weights of the recommendation score (documented in docs/metrics.md)
DEFAULT_WEIGHTS: dict[str, float] = {"utilization": 0.5, "replication": 0.2, "cnc": 0.3}

#: metric table rows: (label, key, format, higher_is_better)
METRIC_ROWS: list[tuple[str, str, str, bool | None]] = [
    ("Material utilization", "utilization_pct", "{:.1f}%", True),
    ("Utilization (gross of kerf)", "utilization_gross_pct", "{:.1f}%", True),
    ("Waste", "waste_pct", "{:.1f}%", False),
    ("Sheets used", "sheet_count", "{}", False),
    ("Unique sheet layouts", "unique_sheet_layouts", "{}", False),
    ("Sheet replication efficiency", "replication_efficiency", "{:.2f}", True),
    ("Parts placed", "placed_count", "{}", True),
    ("Parts unplaced", "unplaced_count", "{}", False),
    ("Total cut length", "total_cut_length_mm", "{:,.0f} mm", False),
    ("Pierce count", "pierce_count", "{}", False),
    ("Rapid travel (est.)", "rapid_travel_mm", "{:,.0f} mm", False),
    ("Direction changes", "direction_changes", "{}", False),
    ("Min edge clearance", "min_edge_clearance_mm", "{:.1f} mm", True),
    ("Waste skeleton connected", "skeleton_connected", "{}", True),
    ("Skeleton components", "skeleton_components", "{}", False),
    ("Common-line candidates", "common_line_opportunities", "{}", True),
    ("Runtime", "runtime_s", "{:.2f} s", False),
]

_EPS = 1e-9


def build_report(
    job: dict,
    results: dict[str, NestingResult],
    weights: dict[str, float] | None = None,
) -> dict:
    """Assemble the complete comparison report for one or more strategies."""
    weights = weights or DEFAULT_WEIGHTS
    names = sorted(results)

    strategies: dict[str, dict] = {}
    metrics: dict[str, dict] = {}
    for name in names:
        result = results[name]
        strategy_metrics = compute_metrics(result)
        strategy_metrics["runtime_s"] = result.runtime_s
        metrics[name] = strategy_metrics
        strategies[name] = {
            "runtime_s": round(result.runtime_s, 3),
            "metrics": strategy_metrics,
            "unplaced": [
                {"part_id": p.part_id, "name": p.name, "quantity": p.quantity}
                for p in result.unplaced
            ],
            "sheets": [
                {
                    "index": sheet.index,
                    "copies": sheet.copies,
                    "placements": [
                        {
                            "part_id": p.part.part_id,
                            "name": p.part.name,
                            "x": round(p.x, 3),
                            "y": round(p.y, 3),
                            "rotation_deg": round(p.rotation_deg, 3),
                            "mirrored": p.mirrored,
                        }
                        for p in sheet.placements
                    ],
                    "offcuts": [
                        [[round(x, 2), round(y, 2)] for x, y in polygon.exterior.coords]
                        for polygon in sheet.offcuts
                    ],
                }
                for sheet in result.sheets
            ],
        }

    table = _comparison_table(metrics, names)
    recommendation = _recommendation(metrics, names, weights) if len(names) > 1 else None

    return {
        "schema_version": 1,
        "generated_by": f"dxf-nesting-optimizer {__version__}",
        "job": job,
        "strategies": strategies,
        "comparison": {"table": table, "recommendation": recommendation},
    }


def _comparison_table(metrics: dict[str, dict], names: list[str]) -> list[dict]:
    table = []
    for label, key, fmt, higher_better in METRIC_ROWS:
        row: dict = {"metric": label, "key": key}
        for name in names:
            value = metrics[name].get(key)
            row[name] = fmt.format(value) if isinstance(value, (int, float)) else value
        row["better"] = _better_strategy(metrics, names, key, higher_better)
        table.append(row)
    return table


def _better_strategy(
    metrics: dict[str, dict], names: list[str], key: str, higher_better: bool | None
) -> str | None:
    if higher_better is None or len(names) < 2:
        return None
    values = [metrics[name].get(key, 0.0) for name in names]
    best = max(values) if higher_better else min(values)
    winners = [name for name, value in zip(names, values, strict=True) if abs(value - best) <= _EPS]
    if len(winners) == len(names) or len(winners) != 1:
        return None
    return winners[0]


def _recommendation(metrics: dict[str, dict], names: list[str], weights: dict[str, float]) -> dict:
    scores = {name: _score(metrics[name], weights) for name in names}
    winner = sorted(names, key=lambda n: (-scores[n], n))[0]

    rationale: list[str] = []
    if len(names) == 2:
        a, b = names
        rationale = _rationale(metrics, a, b, winner)

    return {
        "strategy": winner,
        "scores": {name: round(score, 3) for name, score in scores.items()},
        "weights": weights,
        "rationale": rationale,
    }


def _score(metrics: dict, weights: dict[str, float]) -> float:
    utilization = metrics["utilization_pct"] / 100.0
    replication = metrics["replication_efficiency"]
    cut = metrics["total_cut_length_mm"]
    rapid = metrics["rapid_travel_mm"]
    cut_ratio = cut / (cut + rapid) if (cut + rapid) > 0 else 1.0
    connectivity = (
        1.0 / metrics["skeleton_components"] if metrics["skeleton_components"] > 0 else 1.0
    )
    cnc = 0.5 * connectivity + 0.5 * cut_ratio
    return (
        weights["utilization"] * utilization
        + weights["replication"] * replication
        + weights["cnc"] * cnc
    )


def _rationale(metrics: dict[str, dict], a: str, b: str, winner: str) -> list[str]:
    """Human-readable reasons for the recommendation (max 5 bullets)."""
    ma, mb = metrics[a], metrics[b]
    notes: list[str] = []

    sheet_diff = ma["sheet_count"] - mb["sheet_count"]
    if sheet_diff != 0:
        fewer = a if sheet_diff < 0 else b
        notes.append(f"{fewer} needs {abs(sheet_diff)} fewer sheet(s)")

    util_diff = ma["utilization_pct"] - mb["utilization_pct"]
    if abs(util_diff) >= 1.0:
        better = a if util_diff > 0 else b
        notes.append(f"{better} achieves {abs(util_diff):.1f} points higher utilization")

    rep_a, rep_b = ma["replication_efficiency"], mb["replication_efficiency"]
    for name, rep, other_rep in ((a, rep_a, rep_b), (b, rep_b, rep_a)):
        if rep >= 0.999 and other_rep < 0.5:
            copies = ", ".join(str(c) for c in (ma if name == a else mb)["copy_counts"])
            notes.append(
                f"{name} produces identical repeatable sheets (machine once, repeat; "
                f"copies per layout: {copies})"
            )
            break

    conn = [n for n in (a, b) if (ma if n == a else mb)["skeleton_connected"]]
    not_conn = [n for n in (a, b) if n not in conn]
    if conn and not_conn:
        notes.append(f"{conn[0]} keeps the waste skeleton connected (easier clamping)")

    cut_diff = ma["total_cut_length_mm"] - mb["total_cut_length_mm"]
    if abs(cut_diff) / max(1.0, max(ma["total_cut_length_mm"], mb["total_cut_length_mm"])) >= 0.03:
        shorter = a if cut_diff < 0 else b
        notes.append(f"{shorter} has the shorter total cut length")

    return notes[:5]
