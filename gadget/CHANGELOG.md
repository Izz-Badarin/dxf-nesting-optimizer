# Najjar Pro — Changelog

Commercial Vectric gadget for parametric cabinet building.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.8.0] — 2026-09-23

### Added
- **Sheet nesting** (`nest.lua`): parts packed onto real boards with kerf and
  trim margins — per-sheet SVG layouts with labels, dimensions and grain
  arrows, utilization %, sheet count in the console and `job.json`.
  Doors/fronts/plinths never rotate (grain + edge banding).
- **Cost estimate** (`cost.lua`): boards (real nested count x price/m2),
  edge-banding metres, counted hardware units x unit price. Every price is
  user-editable (spec/defaults `pricing` block + `price` field in each
  hardware JSON). Printed, appended to the BOM CSV, stored in `job.json`.
- **Plinth / toe-kick** (`construction.plinth = {height, recess, thickness}`):
  euro-standard strip under the body — own part, BOM note with the recess,
  3D box under the lifted body, explodes downward.
- Viewer: touch support (one finger rotate, pinch zoom) for shop tablets.
- Fuzz-hardening test suite (hostile JSON/CSV/spec inputs never crash),
  i18n parity test (every key exists in EN/HE/AR).
- `sheet.kerf` / `sheet.margin` user settings; `pricing` spec block;
  `templates/base-plinth.json` demo; hardware JSONs carry editable
  placeholder prices.

### Fixed
- `importer.from_foreign` crashed on a nil map file.
- LED-channel hardware was never listed in the cost table.
- First nesting sheet was never created (all parts "unplaced") — packing now
  bootstraps correctly.
- CSV cut lists: semicolon (European) and tab delimiters auto-detected;
  decimal commas parse (`560,5` -> 560.5).
- JSON decoder: deeply-nested hostile input errors cleanly (depth limit 200)
  instead of overflowing the stack.

## [0.7.0] — 2026-09-23

### Added
- Interactive 3D viewer (`viewer.html`): self-contained canvas 3D engine —
  drag-rotate, zoom, Front/Isometric/Top, **explode slider**, clickable parts
  list, dimension-check panel. Fully offline, trilingual (EN/HE/AR, RTL).
- Dimension checker (`check.lua`): part-vs-board errors, rotate-only info,
  narrow/low doors, low drawer fronts, box-taller-than-front, hinge count by
  door height, groove over half thickness, shelf setback.
- Foreign-config import (`importer.lua`, `convert.lua`, `importers/*.json`
  map files): other apps' JSON configs via alias maps (new app = new map,
  no code changes); CSV cut lists with EN/HE/AR headers; loose-parts mode.
- 3D model builder (`model3d.lua`) with role colors and explode vectors.

## [0.6.0] — 2026-09-23

### Added
- Installable VCarve/Aspire gadget shell (`NajjarPro.vgadget`): wizard dialog,
  draws parts into the job on the layer contract, BOM + DXF to `out/`.
- Packaging (Linux shell script + Windows PowerShell), CI packaging step.

## [0.5.0] — 2026-09-22
Hardware library (JSON, user-editable): Cabineo, shelf pins, hinge cups,
drawer slides, dowels, Rafix, LED channel. System-32 patterns, flip layers.

## [0.4.0] — 2026-09-22
Trilingual BOM (EN/HE/AR, UTF-8 + BOM for Excel), units (mm/in), edge banding.

## [0.3.0] — 2026-09-21
Zones (open/door/drawers), dividers, per-bay shelves, drawer boxes,
LED groove metadata.

## [0.2.0] — 2026-09-21
DXF R12 export (layer per operation), nesting preview SVG, job.json.

## [0.1.0] — 2026-09-20
First headless core: spec normalization + validation, euro box decomposition,
BOM, golden test suite.
