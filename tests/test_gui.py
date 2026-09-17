"""API tests for the web GUI (milestone: fusion GUI)."""

from __future__ import annotations

import pytest

fastapi = pytest.importorskip("fastapi")
httpx = pytest.importorskip("httpx")
from fastapi.testclient import TestClient  # noqa: E402

from nesting.gui.app import app  # noqa: E402

client = TestClient(app, raise_server_exceptions=False)


class TestGui:
    def test_index_served(self):
        response = client.get("/")
        assert response.status_code == 200
        assert "dxf-nesting-optimizer" in response.text
        assert "Run nesting" in response.text

    def test_static_assets(self):
        for asset in ("style.css", "app.js"):
            response = client.get(f"/static/{asset}")
            assert response.status_code == 200

    def test_examples_listed(self):
        response = client.get("/api/examples")
        assert response.status_code == 200
        assert "furniture_parts.dxf" in response.json()["examples"]

    def test_nest_example(self):
        response = client.post(
            "/api/nest",
            data={
                "example": "furniture_parts.dxf",
                "sheet_width": 1220,
                "sheet_height": 2440,
                "tool_diameter": 6,
                "clearance": 4,
                "edge_clearance": 10,
                "rotation_step": 90,
                "allow_mirror": "true",
                "depth": 2,
            },
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["job_id"]
        assert set(payload["strategies"]) == {"symmetry-first", "waste-first"}
        for strategy in payload["strategies"].values():
            assert strategy["sheets"]
            sheet = strategy["sheets"][0]
            assert sheet["placements"]
            placement = sheet["placements"][0]
            assert placement["polygon"] and placement["color"]
        assert payload["comparison"]["recommendation"]["strategy"]
        return str(payload["job_id"])

    def _job_id(self) -> str:
        return self.test_nest_example()

    def test_nest_requires_source(self):
        response = client.post("/api/nest", data={})
        assert response.status_code == 400

    def test_unknown_example(self):
        response = client.post("/api/nest", data={"example": "nope.dxf"})
        assert response.status_code == 404

    def test_downloads(self):
        job_id = self.test_nest_example()
        for url in (
            f"/api/download/dxf/{job_id}/waste-first",
            f"/api/download/dxf/{job_id}/symmetry-first",
            f"/api/download/report/{job_id}/json",
            f"/api/download/report/{job_id}/md",
            f"/api/download/pdf/{job_id}",
        ):
            response = client.get(url)
            assert response.status_code == 200, url
            assert len(response.content) > 500, url
        assert client.get("/api/download/dxf/deadbeef/waste-first").status_code == 404

    def test_upload(self, tmp_path):
        source = (
            __import__("pathlib").Path(__file__).parents[1]
            / "examples"
            / "inputs"
            / "mixed_curved.dxf"
        )
        with source.open("rb") as handle:
            response = client.post(
                "/api/nest",
                files={"file": ("mixed_curved.dxf", handle, "application/dxf")},
                data={"sheet_width": 1220, "sheet_height": 2440},
            )
        assert response.status_code == 200
        assert response.json()["strategies"]["waste-first"]["sheets"]
