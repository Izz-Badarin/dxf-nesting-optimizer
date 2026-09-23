# Najjar Pro — Changelog

Commercial Vectric gadget for parametric cabinet building.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.10.0] — 2026-09-23

### Added
- **Board-ready drawing into VCarve** (`vectric.render_sheets`): the
  gadget can now draw the *nested boards* into the job — every part at its
  packed position on each board, features rotated with rotated parts
  (90° in-plane, never mirrored), part labels on `ETCH`, board boundaries
  on `CNC_BOUNDARY`, board labels on `INFO`. The VCarve job becomes the
  cut file. Wizard switch: *Draw nested boards* (default on); off = the
  classic per-part layout for editing.
- **First-run environment self-check** (`NajjarShell.self_check`): inside
  VCarve the gadget verifies the API surface it needs (VectricJob,
  HTML_Dialog, Contour, CreateCadContour, …) and reports anything missing
  in one clear message — the first live run is diagnosable, not a mystery
  error. ToolpathManager is checked as optional.

## [0.9.0] — 2026-09-23

### Added
- **Three-page wizard** in the gadget shell (Cabinet → Interior → Hardware
  & boards). Every configuration is now user-enterable inside VCarve:
  drawer zone (count), plinth/toe-kick (height), board size, saw kerf,
  trim margin, and all cost prices (board/m2, edge/m, currency).
- **One-click toolpath templates**: drop `<layer>.ToolpathTemplate` files
  into the gadget's `toolpaths/` folder (created once via VCarve's
  *Save Template As…*) and the shell loads them through the verified
  `ToolpathManager:LoadToolpathTemplate` API after drawing — the toolpath
  list fills itself. `toolpaths/README.md` documents the 10-minute setup.
- Drawer zone in the wizard: 250 mm per drawer, drawer boxes included,
  doors or an open zone above automatically.

### Fixed
- Wizard currency field sanitized (letters only, falls back to ILS).

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
