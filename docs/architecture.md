# Architecture

## Layers

```
Layer 4  Interfaces     CLI (v0.1) → Web GUI + API (v1.0)
Layer 3  Production     labels · offcut inventory · G-code posts · batch jobs   (phase 3+)
Layer 2  Analysis       dual-strategy comparison · metrics · recommendation ·
                        JSON/Markdown/PDF reports · benchmark suite
Layer 1  Nesting engine Strategy interface · symmetry-first · waste-first ·
                        heuristics → NFP true-shape → SA refinement            (phases 1–2)
Layer 0  Geometry kernel DXF I/O (ezdxf) · contours/holes · flattening ·
                        transforms · symmetry detection (Shapely)
```

Every layer works headless — the engine is a library first; the CLI is a thin
skin and the future web GUI will be another.

## Module map

| Module | Responsibility |
|---|---|
| `nesting.config` | `SheetSpec` (1220×2440 default), `NestSettings` (ArtCAM-style spacing model, rotation step, mirror toggle, curve tolerance, calculation depth) |
| `nesting.geometry.entities` | lightweight entity records (line, arc, circle, polyline) kept for arc-preserving export later |
| `nesting.geometry.polygon_utils` | arc flattening (sagitta-bounded), ring stitching, polygon repair, mirror/rotate/translate transforms |
| `nesting.geometry.part` | the `Part` model: normalized outline + holes, quantity, metadata, area/bbox, collision shape, identity signature |
| `nesting.geometry.symmetry` | mirror-axis detection, mirror-pair similarity (drives symmetry-first nesting) |
| `nesting.io.dxf_import` | DXF → validated parts (units, block explosion, stitching, even-odd grouping, merging) |
| `nesting.io.dxf_export` | `NestingResult` → CNC-ready DXF (M3) |
| `nesting.io.pdf_report` | sheet visualizations → PDF (M5) |
| `nesting.nesting.base` | `Strategy` ABC, `Placement`, `SheetLayout` (with copy-count merging), `NestingResult` |
| `nesting.nesting.waste_first` | waste-minimization engine (M3) |
| `nesting.nesting.symmetry_first` | mirrored/tiled pattern engine (M4) |
| `nesting.analysis.metrics` | utilization, waste, sheet replication, CNC factors |
| `nesting.analysis.compare` | side-by-side comparison + recommendation (M5) |
| `nesting.analysis.report` | JSON/Markdown report writers |
| `nesting.nesting.common` | orientation variants, placement math, offcuts, identical-sheet merging, validation |
| `nesting.nesting.heuristics` | MaxRects bin packing and true-shape bottom-left-fill |
| `nesting.gui` | FastAPI web app + static single-page UI |

## Import pipeline (M1)

```
read file (recover fallback)
  → unit detection ($INSUNITS / override) → scale to mm
  → explode INSERTs (recursive virtual entities)
  → flatten curves with sagitta tolerance
  → stitch open line/arc chains into rings
  → even-odd containment grouping (parts / holes / islands)
  → attach contained TEXT as metadata
  → normalize to origin, merge identical parts (quantity)
  → validate; warnings for everything quarantined
```

## Placement semantics (M3)

Part outlines are normalized so the bbox minimum corner sits at `(0, 0)`.
A `Placement` applies, in order: **mirror** (about x=0) → **rotate**
(about origin, CCW, multiples of the rotation step) → **translate** to `(x, y)`
on the sheet. Collision tests use outlines grown by
`NestSettings.collision_grow` (half the part spacing).

## Determinism

Stable sorts, no unseeded randomness, fixed candidate orders. Identical input
files must always produce identical nesting output — this is enforced by the
golden tests and required by the comparison feature (two runs of the same
strategy must not differ).

## Milestones

| # | Deliverable | Status |
|---|---|---|
| M0 | scaffold: packaging, docs, CI, package skeleton | ✅ |
| M1 | DXF import → validated `Part` model | ✅ |
| M2 | geometry core: transforms, stitching, symmetry, part model | ✅ |
| GUI | web GUI: drag-drop, side-by-side sheets, downloads | ✅ |
| M3 | waste-first nesting (multi-sheet) + DXF export | ✅ |
| M4 | symmetry-first nesting + export | ✅ |
| M5 | metrics + comparison reports (JSON/MD) + PDF | ✅ |
| M6 | CLI polish, examples, full docs → v0.1.0 | ✅ |
