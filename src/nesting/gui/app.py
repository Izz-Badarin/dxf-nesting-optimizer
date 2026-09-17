"""FastAPI backend for the web GUI.

Serves the single-page UI from ``static/`` and exposes:

* ``POST /api/nest`` - import a DXF (upload or example), run both nesting
  strategies, return the full comparison payload with sheet geometry
* ``GET /api/download/...`` - generated DXF / report / PDF downloads

The browser only ever talks to this backend via relative URLs, so the app
works behind any reverse proxy (including the Arena preview).
"""

from __future__ import annotations

import shutil
import tempfile
import uuid
from collections import OrderedDict
from dataclasses import asdict
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .. import NestSettings, SheetSpec, import_dxf
from .._version import __version__
from ..analysis.compare import build_report
from ..analysis.report import write_json_report, write_markdown_report
from ..io.dxf_export import export_nesting_dxf
from ..io.pdf_report import export_nesting_pdf
from ..nesting.common import merge_identical_sheets
from ..nesting.symmetry_first import SymmetryFirstStrategy
from ..nesting.waste_first import WasteFirstStrategy

_STATIC = Path(__file__).parent / "static"
_MAX_UPLOAD_BYTES = 50 * 1024 * 1024
_MAX_JOBS = 6

app = FastAPI(title="dxf-nesting-optimizer", version=__version__)
app.mount("/static", StaticFiles(directory=_STATIC), name="static")

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


class _Job:
    """A processed nesting job plus lazily generated download files."""

    def __init__(self, source_name: str, results: dict, report: dict) -> None:
        self.source_name = source_name
        self.results = results
        self.report = report
        self.tmpdir = Path(tempfile.mkdtemp(prefix="dxfnest-"))
        self.generated: dict[str, Path] = {}

    def file(self, key: str, builder) -> Path:
        if key not in self.generated:
            path = self.tmpdir / key
            builder(path)
            self.generated[key] = path
        return self.generated[key]


_JOBS: OrderedDict[str, _Job] = OrderedDict()


def _evict_jobs() -> None:
    while len(_JOBS) > _MAX_JOBS:
        _, job = _JOBS.popitem(last=False)
        shutil.rmtree(job.tmpdir, ignore_errors=True)


def _examples_dir() -> Path | None:
    """Locate the bundled example DXF files (repo checkout or CWD)."""
    candidates = [
        Path(__file__).resolve().parents[4] / "examples" / "inputs",
        Path.cwd() / "examples" / "inputs",
    ]
    for candidate in candidates:
        if candidate.is_dir() and any(candidate.glob("*.dxf")):
            return candidate
    return None


@app.get("/")
def index() -> FileResponse:
    return FileResponse(_STATIC / "index.html")


@app.get("/api/examples")
def list_examples() -> dict:
    directory = _examples_dir()
    if directory is None:
        return {"examples": []}
    examples = sorted(p.name for p in directory.glob("*.dxf"))
    return {"examples": examples}


@app.post("/api/nest")
async def nest(
    file: Annotated[UploadFile | None, File(description="DXF upload")] = None,
    example: Annotated[str | None, Form()] = None,
    sheet_width: Annotated[float, Form()] = 1220.0,
    sheet_height: Annotated[float, Form()] = 2440.0,
    tool_diameter: Annotated[float, Form()] = 6.0,
    clearance: Annotated[float, Form()] = 4.0,
    edge_clearance: Annotated[float, Form()] = 10.0,
    rotation_step: Annotated[float, Form()] = 90.0,
    allow_mirror: Annotated[bool, Form()] = True,
    depth: Annotated[int, Form()] = 2,
) -> dict:
    source_path: Path
    if file is not None:
        data = await file.read()
        if len(data) > _MAX_UPLOAD_BYTES:
            raise HTTPException(413, "file too large (50 MB limit)")
        if not data:
            raise HTTPException(400, "empty upload")
        source_path = Path(tempfile.gettempdir()) / f"dxfnest-upload-{uuid.uuid4().hex}.dxf"
        source_path.write_bytes(data)
        source_name = file.filename or "upload.dxf"
    elif example:
        directory = _examples_dir()
        if directory is None:
            raise HTTPException(404, "no examples available in this installation")
        candidate = (directory / example).resolve()
        if directory.resolve() not in candidate.parents or not candidate.exists():
            raise HTTPException(404, f"unknown example '{example}'")
        source_path = candidate
        source_name = example
    else:
        raise HTTPException(400, "provide a DXF upload or choose an example")

    if min(sheet_width, sheet_height) <= 0:
        raise HTTPException(400, "sheet dimensions must be positive")

    settings = NestSettings(
        sheet=SheetSpec(width=sheet_width, height=sheet_height),
        tool_diameter=tool_diameter,
        toolpath_clearance=clearance,
        edge_clearance=edge_clearance,
        rotation_step_deg=rotation_step,
        allow_mirror=allow_mirror,
        calculation_depth=max(1, min(5, depth)),
    )

    imported = import_dxf(source_path, settings)
    if not imported.parts:
        raise HTTPException(422, "no nestable parts found in the DXF file")

    total_area = sum(p.area * p.quantity for p in imported.parts)
    job = {
        "source_file": source_name,
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

    results = {}
    for name, strategy_cls in (
        ("symmetry-first", SymmetryFirstStrategy),
        ("waste-first", WasteFirstStrategy),
    ):
        results[name] = strategy_cls().timed_nest(imported.parts, settings)

    report = build_report(job, results)
    payload = _payload(job, imported, results, report)

    job_id = uuid.uuid4().hex[:12]
    _JOBS[job_id] = _Job(source_name, results, report)
    _evict_jobs()
    payload["job_id"] = job_id
    return payload


def _payload(job: dict, imported, results: dict, report: dict) -> dict:
    """Response payload: report data plus sheet geometry for rendering."""
    part_ids = sorted(p.part_id for p in imported.parts)
    colors = {pid: _PALETTE[i % len(_PALETTE)] for i, pid in enumerate(part_ids)}

    parts = [
        {
            "part_id": p.part_id,
            "name": p.name,
            "layer": p.layer,
            "quantity": p.quantity,
            "width": round(p.width, 1),
            "height": round(p.height, 1),
            "area": round(p.area, 1),
            "holes": len(p.holes),
            "color": colors[p.part_id],
        }
        for p in sorted(imported.parts, key=lambda p: p.part_id)
    ]

    strategies = {}
    for name, result in results.items():
        sheets = []
        sheet_area = result.settings.sheet.area
        for sheet in merge_identical_sheets(result.sheets):
            used = sum(p.part.area for p in sheet.placements)
            sheets.append(
                {
                    "index": sheet.index,
                    "copies": sheet.copies,
                    "utilization_pct": round(100.0 * used / sheet_area, 1),
                    "placements": [
                        {
                            "part_id": placement.part.part_id,
                            "name": placement.part.name,
                            "color": colors.get(placement.part.part_id, "#cccccc"),
                            "mirrored": placement.mirrored,
                            "rotation_deg": placement.rotation_deg,
                            "polygon": _ring(placement.polygon),
                            "holes": [_ring(h) for h in placement.hole_polygons],
                        }
                        for placement in sheet.placements
                    ],
                    "offcuts": [_ring(o) for o in sheet.offcuts],
                }
            )
        strategies[name] = {
            "metrics": report["strategies"][name]["metrics"],
            "runtime_s": report["strategies"][name]["runtime_s"],
            "unplaced": report["strategies"][name]["unplaced"],
            "sheets": sheets,
        }

    return {
        "job": job,
        "parts": parts,
        "strategies": strategies,
        "comparison": report["comparison"],
    }


def _ring(polygon) -> list[list[float]]:
    return [[round(x, 1), round(y, 1)] for x, y in polygon.exterior.coords]


def _get_job(job_id: str) -> _Job:
    job = _JOBS.get(job_id)
    if job is None:
        raise HTTPException(404, "unknown or expired job id - run the nesting again")
    return job


@app.get("/api/download/dxf/{job_id}/{strategy}")
def download_dxf(job_id: str, strategy: str) -> FileResponse:
    job = _get_job(job_id)
    if strategy not in job.results:
        raise HTTPException(404, f"unknown strategy '{strategy}'")
    filename = f"{Path(job.source_name).stem}_{strategy}.dxf"

    def build(path: Path) -> None:
        export_nesting_dxf(job.results[strategy], path, job.source_name)

    return FileResponse(
        job.file(f"{strategy}.dxf", build), filename=filename, media_type="image/vnd.dxf"
    )


@app.get("/api/download/report/{job_id}/{fmt}")
def download_report(job_id: str, fmt: str) -> FileResponse:
    job = _get_job(job_id)
    if fmt not in ("json", "md"):
        raise HTTPException(404, "report format must be json or md")

    def build(path: Path) -> None:
        if fmt == "json":
            write_json_report(job.report, path)
        else:
            write_markdown_report(job.report, path)

    filename = f"comparison_report.{fmt}"
    return FileResponse(
        job.file(filename, build), filename=filename, media_type="application/octet-stream"
    )


@app.get("/api/download/pdf/{job_id}")
def download_pdf(job_id: str) -> FileResponse:
    job = _get_job(job_id)
    filename = f"{Path(job.source_name).stem}_comparison.pdf"

    def build(path: Path) -> None:
        export_nesting_pdf(list(job.results.values()), path, comparison=job.report)

    return FileResponse(job.file(filename, build), filename=filename, media_type="application/pdf")
