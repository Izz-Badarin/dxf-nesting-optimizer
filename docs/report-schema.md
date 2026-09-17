# Comparison report schema (M5 — planned)

The comparison report is emitted as JSON (machine-readable) and Markdown
(human-readable) from the same data. This document defines the JSON shape; it
is implemented in milestone M5 and frozen for v0.1.0.

```jsonc
{
  "job": {
    "source_file": "furniture_parts.dxf",
    "dxf_version": "AC1027",
    "unit": "millimeters",
    "sheet": { "width": 1220.0, "height": 2440.0 },
    "settings": { /* NestSettings snapshot */ },
    "parts": { "unique": 5, "total_quantity": 18, "total_area_mm2": 5123456.7 }
  },
  "strategies": {
    "symmetry-first": {
      "sheets": [
        {
          "index": 1,
          "copies": 3,                       // identical-sheet merging
          "placements": [
            { "part_id": "P001", "x": 10.0, "y": 10.0,
              "rotation_deg": 0.0, "mirrored": false }
          ],
          "offcuts": [ /* remaining usable regions as polygons */ ]
        }
      ],
      "unplaced": [],
      "runtime_s": 0.42,
      "metrics": {
        "utilization_pct": 78.4,
        "utilization_gross_pct": 82.1,
        "waste_pct": 21.6,
        "sheet_count": 4,
        "replication_efficiency": 0.67,
        "unique_sheet_layouts": 2,
        "cnc": {
          "total_cut_length_mm": 18234.5,
          "pierce_count": 71,
          "rapid_travel_mm": 4521.0,
          "direction_changes": 318,
          "min_edge_clearance_mm": 10.2,
          "skeleton_connected": true,
          "common_line_opportunities": 12
        }
      }
    },
    "waste-first": { /* same structure */ }
  },
  "comparison": {
    "table": [ /* metric rows: name, symmetry value, waste value, better */ ],
    "recommendation": {
      "strategy": "waste-first",
      "score": { "symmetry-first": 0.71, "waste-first": 0.84 },
      "weights": { "utilization": 0.5, "replication": 0.2, "cnc": 0.3 },
      "rationale": ["waste-first saves 1 sheet (−25%) ..."]
    }
  }
}
```

Notes:

* Polygons (offcuts) are serialized as coordinate rings, 3-decimal precision.
* The Markdown report renders the same data with per-sheet diagrams.
* The schema is versioned (`"schema_version": 1`) once M5 lands.
