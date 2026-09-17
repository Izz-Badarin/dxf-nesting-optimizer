"""End-to-end tests: DXF export round-trip, reports, PDF (milestones M3-M5)."""

from __future__ import annotations

import json
from dataclasses import asdict
from pathlib import Path

import pytest

from nesting import NestSettings, SymmetryFirstStrategy, WasteFirstStrategy, import_dxf
from nesting.analysis.compare import build_report
from nesting.analysis.report import write_json_report, write_markdown_report
from nesting.io.dxf_export import export_nesting_dxf
from nesting.io.pdf_report import export_nesting_pdf, render_sheet_png

INPUTS = Path(__file__).parents[1] / "examples" / "inputs"


@pytest.fixture(scope="module")
def furniture_job():
    imported = import_dxf(INPUTS / "furniture_parts.dxf")
    settings = NestSettings()
    results = {
        "symmetry-first": SymmetryFirstStrategy().timed_nest(imported.parts, settings),
        "waste-first": WasteFirstStrategy().timed_nest(imported.parts, settings),
    }
    return imported, settings, results


def _job_dict(imported, settings) -> dict:
    return {
        "source_file": "furniture_parts.dxf",
        "dxf_version": imported.stats.get("dxf_version"),
        "unit": imported.source_unit,
        "sheet": {"width": settings.sheet.width, "height": settings.sheet.height},
        "settings": asdict(settings),
        "parts": {
            "unique": len(imported.parts),
            "total_quantity": imported.total_quantity,
            "total_area_mm2": round(sum(p.area * p.quantity for p in imported.parts), 3),
        },
    }


class TestDxfExport:
    def test_round_trip(self, furniture_job, tmp_path):
        imported, settings, results = furniture_job
        result = results["waste-first"]
        out = export_nesting_dxf(result, tmp_path / "nested.dxf", "furniture_parts.dxf")
        assert out.exists() and out.stat().st_size > 1000

        # re-import the exported file: every CUT-layer part must come back
        reimported = import_dxf(out)
        cut_parts = [p for p in reimported.parts if p.layer == "CUT"]
        assert sum(p.quantity for p in cut_parts) == result.total_placements
        # holes survive as holes: a CUT part with 4 holes and side-panel area
        source_side = next(p for p in imported.parts if p.name == "SIDE_PANEL")
        side = next(p for p in cut_parts if len(p.holes) == 4)
        assert side.area == pytest.approx(source_side.area, rel=1e-3)
        # ETCH labels: one per placement, written directly into the file
        import ezdxf

        doc = ezdxf.readfile(out)
        etch = [e for e in doc.modelspace() if e.dxftype() == "TEXT" and e.dxf.layer == "ETCH"]
        assert len(etch) == result.total_placements
        # offcuts and boundaries are present too
        assert any(p.layer == "OFFCUT" for p in reimported.parts)
        assert any(p.layer == "CNC_BOUNDARY" for p in reimported.parts)

    def test_identical_sheets_merged_in_export(self, furniture_job, tmp_path):
        import ezdxf

        from nesting.nesting.common import merge_identical_sheets

        imported, settings, results = furniture_job
        result = results["symmetry-first"]
        out = export_nesting_dxf(result, tmp_path / "sym.dxf")
        doc = ezdxf.readfile(out)
        titles = [
            e.dxf.text for e in doc.modelspace() if e.dxftype() == "TEXT" and e.dxf.layer == "INFO"
        ]
        merged = merge_identical_sheets(result.sheets)
        assert len(titles) == len(merged)  # one INFO title per unique sheet
        if any(sheet.copies > 1 for sheet in merged):
            assert any("copies" in t for t in titles)


class TestComparison:
    def test_report_structure(self, furniture_job):
        imported, settings, results = furniture_job
        report = build_report(_job_dict(imported, settings), results)
        assert report["schema_version"] == 1
        assert set(report["strategies"]) == {"symmetry-first", "waste-first"}
        for _name, strategy in report["strategies"].items():
            metrics = strategy["metrics"]
            for key in (
                "utilization_pct",
                "waste_pct",
                "sheet_count",
                "replication_efficiency",
                "total_cut_length_mm",
                "pierce_count",
                "rapid_travel_mm",
                "skeleton_connected",
            ):
                assert key in metrics
            assert strategy["sheets"]
        table = report["comparison"]["table"]
        assert table and all(
            set(row) >= {"metric", "symmetry-first", "waste-first", "better"} for row in table
        )

    def test_recommendation(self, furniture_job):
        imported, settings, results = furniture_job
        report = build_report(_job_dict(imported, settings), results)
        rec = report["comparison"]["recommendation"]
        assert rec["strategy"] in results
        assert set(rec["scores"]) == set(results)
        assert rec["rationale"]
        waste_metrics = report["strategies"]["waste-first"]["metrics"]
        sym_metrics = report["strategies"]["symmetry-first"]["metrics"]
        if waste_metrics["utilization_pct"] > sym_metrics["utilization_pct"] + 5:
            assert rec["strategy"] == "waste-first"


class TestReportWriters:
    def test_json_and_markdown(self, furniture_job, tmp_path):
        imported, settings, results = furniture_job
        report = build_report(_job_dict(imported, settings), results)
        json_path = write_json_report(report, tmp_path / "report.json")
        md_path = write_markdown_report(report, tmp_path / "report.md")
        loaded = json.loads(json_path.read_text())
        assert loaded["schema_version"] == 1
        md = md_path.read_text()
        assert "# Nesting comparison report" in md
        assert "## Recommendation" in md
        assert "utilization" in md.lower()
        assert json_path.stat().st_size > 500


class TestPdf:
    def test_pdf_generated(self, furniture_job, tmp_path):
        imported, settings, results = furniture_job
        report = build_report(_job_dict(imported, settings), results)
        pdf_path = export_nesting_pdf(
            [results["symmetry-first"], results["waste-first"]],
            tmp_path / "comparison.pdf",
            comparison=report,
        )
        data = pdf_path.read_bytes()
        assert data.startswith(b"%PDF")
        assert len(data) > 20_000

    def test_sheet_png(self, furniture_job, tmp_path):
        imported, settings, results = furniture_job
        png = render_sheet_png(
            results["waste-first"], results["waste-first"].sheets[0], tmp_path / "s.png"
        )
        assert png.read_bytes().startswith(b"\x89PNG")
