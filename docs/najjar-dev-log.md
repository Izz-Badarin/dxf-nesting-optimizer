# Najjar Pro — Development Log

## 2026-09-23 — v0.6.0: the VCarve gadget shell ✅

**Research:** vectric.com is network-blocked from the sandbox, but public
GitHub gadget repos (tippmar/vectric-gadgets, PaulRowntree) provided the
real API surface: `-- VECTRIC LUA SCRIPT` marker requirement,
`main(script_path)` entry, `VectricJob()/job.Exists`,
`HTML_Dialog(true, html, w, h, title)` + `GetTextField/GetCheckBox`,
`job.LayerManager:GetLayerWithName(name)`, `Contour(0.0)` +
`AppendPoint/LineTo/ArcTo(pt, 1.0)` (bulge 1 = 180° arc → circles),
`layer:AddObject(CreateCadContour(c), true)`, `DisplayMessageBox`.

**Built:**

- **`vcarve/Najjar_Pro.lua`** — the installable entry: loads the headless
  core through `package.preload` (zero core changes — the v0.5 adapter
  bet paid off), a one-page wizard dialog (dimensions, construction,
  hardware, language), validation, generation, drawing into the job, BOM +
  DXF side files
- **`vcarve/najjar_backend.lua`** — the real backend implementing
  `create_layer/polyline/circle/text` against the live Vectric job
  (circles via two 180° arcs; text attempts guarded with pcall)
- **Packaging**: `tools/package-gadget.sh` + `.ps1` →
  `gadget/release/NajjarPro.vgadget` (single-root-folder ZIP, exactly how
  Vectric ships gadgets); CI now packages on every push
- **`test_gadget_shell.lua`** — everything testable without VCarve:
  syntax of both shell files, the required Vectric marker, dialog
  field↔HTML consistency (every id read exists; every input is read),
  assemble_spec goldens (door zones, disabled hardware, bad input
  fallbacks), a full pipeline run from dialog values, and a render through
  the real backend factory against a fake SDK
- Tests: 486 → **545 assertions**

**Status:** the shell has never run inside a live VCarve — first-run
testing is the top item for v0.7, the moment the owner's license arrives.

---

## 2026-09-23 — v0.5.0: corner joinery, edge banding, projects & the Vectric adapter ✅

**Built:**

- **Drawer-box corner joinery** as hardware data: `corner_dowel_8`
  (2 dowels per corner) and `corner_rafix_15` (knock-down) — face holes
  land on the box sides as `DRILL_DOWEL` geometry; the mating EDGE holes
  on the front/back panels (impossible to drill flat on a router) become
  an `edge-drill Ø… ×…` BOM note for the horizontal drill. The library
  carries positions, so a new fitting brand = a new JSON file
- **Edge banding** per part role: built-in defaults (shelves/dividers
  front, doors/fronts all, boxes front, carcass none), spec overrides
  (`edge_banding`), validation, and a translated BOM column in all three
  languages
- **Multi-cabinet projects** (golden 4, `kitchen-job.json`): K1 + two
  identical wall cabinets — parts merge across cabinets into single rows
  with doubled qty (4 wall sides in one row), one project-wide cut list,
  area and sheet estimate; the full job pipeline is deterministic
- **`vectric.lua` — the Vectric adapter**: the core now renders through
  a backend interface (`create_layer/polyline/circle/text`). The mock
  backend records ops (golden-tested: 9 layers, 15 polylines, 161
  circles, 13 texts for the kitchen); `real_backend()` is an explicit
  stub that plugs in during the v0.6 shell work — the core will not
  change when the SDK lands
- Tests: 423 → **486 assertions** (green on first run again)

**Next (v0.6):** the gadget shell — real Vectric backend + wizard
dialogs + toolpath templates. Requires the owner's VCarve Pro license;
until then the headless core is feature-complete and testable.

---

## 2026-09-23 — v0.4.0: slide patterns, divider pins & box joinery ✅

**Built:**

- **Undermount slide locking** from the hardware library: rear Ø10 hole +
  front obround slot on every drawer-box side (brand positions parametric
  in `slide_undermount.json`); `slide_sidemount.json` documents the
  screw-on reality (no machining) so the UI can offer both honestly
- **Divider pin columns**: dividers in adjustable-shelf zones get the
  system-32 ladder on both faces, aligned to the side-panel grid so
  shelves stay level across bays; face-B holes are pre-mirrored onto the
  new `DRILL5_SHELF_FLIP` layer with a flip note — the two-sided-machining
  convention from the product plan, now real
- **Drawer-box bottom joinery**: `"bottom": "lay-in" | "grooved"` —
  grooved boxes get a BOX_GROOVE channel in sides + front/back and a
  bottom sized into the grooves (+2× groove depth)
- **Flip convention decided**: flip about the vertical short axis; flip
  layer features stored pre-mirrored (x → w−x), so symmetric layouts
  coincide visually and CAM just drills after turning the part over
- Tests: 378 → **423 assertions** (all green on first run — the
  hand-computed-goldens discipline is paying off)

**Bugs found & fixed:**

1. **Divider geometry** (found during design review, would have cut
   scrap): v0.3 dividers spanned the full zone height, colliding with the
   bottom panel. A divider connecting to the bottom now starts at the
   bottom panel's top face (and ends below the top panel) — golden 3
   divider is now 682 mm, not 700, and the area dropped to 6.17 m².

**Next (v0.5):** drawer-box corner joinery (dowel/rafix patterns) and the
**VCarve gadget shell** — dialogs, drawing into the job, toolpath
templates. The shell is where the owner's VCarve Pro license becomes
needed.

---

## 2026-09-23 — v0.3.0: dividers, drawer boxes & LED grooves ✅

**Built:**

- **Dividers** inside zones (`dividers: [{at: 300}]` or `[300, 600]`):
  per-bay shelves (count is per bay), divider panels with connector
  machining, and Cabineo drilling on the bottom/top panels at the divider
  line; `field-connect` BOM notes where a divider meets no panel;
  validation (position bounds, min gap = divider thickness) in 3 languages
- **Drawer boxes** (`drawers.box: true`): sides, front/back, lay-in
  bottom — height (120), slide clearance (13/side), depth (D−30), bottom
  thickness (9) all parametric; new `materials.drawer` role
- **LED channel groove** from the hardware library (`led_channel_8x8`):
  parametric groove on the top-panel underside, rendered on `LED_GROOVE`
  in DXF + dashed in SVG, with a **flip note** in the BOM (our face
  convention's answer to two-sided machining)
- **Classic euro construction fix**: with a grooved back, bottom/top and
  dividers are pulled forward of the back zone (D − offset − back
  thickness) so the full-height back rides the side grooves — golden 1/2
  numbers updated accordingly
- **Feature-hash signatures**: identical parts now merge by their full
  machining fingerprint, not just count
- New golden 3 (`kitchen-mixed.json`): divider + bays + boxes + LED in
  one cabinet — 13 unique parts / 24 total / 6.18 m²
- BOM counts only holes/pockets (grooves are noted, not counted)
- Tests: 277 → **378 assertions**, all green; CI gained the kitchen run

**Bugs found & fixed:**

1. Leftover thinking artifact (`intererior_ok`) in the drawer-box
   validation sketch — caught before running, replaced with explicit
   scaled-value checks.
2. Float-to-string comparison in a test (`"300,50"` vs `"300.0,50.0"`).
3. Reminder of the parallel-batch rule: a bash call in the same batch can
   race ahead of file writes — verify with a follow-up run.

**Next (v0.4):** slide drilling patterns (brand data), divider pin
columns, drawer-box joinery options. In parallel: owner tests v0.3 on
real specs; VCarve Pro purchase → gadget-shell spike.

---

## 2026-09-23 — v0.2.0: zones, fronts & full configurability ✅

**Owner direction for this phase:** test before buying licenses; register
the domain once a phase is publishable; the app must be global AND local,
with every configuration (thickness, board size, material, ...) enterable
by the user.

**Built:**

- **Zones**: `open` / `door` / `drawers` per cabinet with per-zone shelf
  counts, door counts (1–4, hinge-side assignment), drawer counts (1–10);
  validation (order, bounds, overlap) with trilingual error messages
- **Fronts**: full-overlay reveal math (`reveal`, `edge` — spec-level
  defaults, per-cabinet override); doors carry hinge side; drawer fronts
  stacked with even reveals
- **Hinge placement** from the hardware library: cup count by door height
  (≤900→2, ≤1600→3, else 4), cup Ø35 + Ø5.5 screws at 52 mm spacing,
  mirrored hinge sides for door pairs (doors stay separate unique parts)
- **Per-role materials**: `materials.side/bottom/top/shelf/door/front`
  thickness + name overrides; every derived dimension follows automatically
- **Configurable sheet size** (`sheet.width/height`) — the estimate adapts
  (9.27 m² → 4 sheets @1220×2440 or 2 @2800×2070)
- **`defaults.json` — the shop baseline**: deep-merged under every spec
  (spec wins); `defaults.json.example` shipped, real file gitignored;
  demo verified: 4-line spec inherits 16 mm MDF + 2800×2070 sheet
- **Inch support end-to-end**: inputs (dims, zones, sheet, reveals) in
  inches, BOM displays inches (`21.65` for a 550 mm side)
- New template `wardrobe-zones.json` (golden 2), `merge.lua` module,
  `estimate_sheets` in geometry; CI gained the wardrobe smoke run
- Tests: 191 → **277 assertions**, all green

**Bugs found & fixed:**

1. Per-cabinet fronts override fell back to built-in defaults instead of
   spec-level defaults — replaced with a raw-units override chain
   (built-ins ← spec ← cabinet).
2. Test arithmetic slip (expected pin 1948; correct is 1938 = 50+59×32).
3. Same-file parallel edits in one batch silently drop all but one edit —
   same-file changes are now applied atomically via a single patch.

**Infrastructure lesson:** everything outside the repo (`/home/user/tools`)
was wiped between sessions; the Lua toolchain now lives in
`tools/` inside the repo (`tools/build-lua.sh` rebuilds it in ~10 s).

**Next (v0.3):** dividers inside zones, drawer boxes, slide + LED groove
placement, back-groove corner logic. In parallel: owner tests v0.2 on real
specs; VCarve Pro purchase → gadget-shell spike.

---

## 2026-09-23 — v0.1.0: headless core built and green ✅

**Scope:** the complete parametric core of the Najjar Pro gadget, developed
headless (no VCarve license needed yet), exactly as planned in
`docs/vcarve-gadget-product-plan.md` §10 step 2.

**Built:**

- `gadget/src/najjar/` — 11 pure-Lua modules (json, i18n, fs, layers, spec,
  rules, hardware, geometry, bom, dxf, svg) — Lua 5.1+ compatible for
  Vectric gadget runtime
- `gadget/hardware/` — data-driven hardware library: shelf_pin_5, cabineo_12,
  hinge_cup_35 (data ready, placement v0.2), slide_undermount (stub)
- `gadget/lang/` — full EN / HE / AR translations (console + BOM + errors)
- `gadget/templates/euro-base-900.json` — the reference cabinet
- `gadget/tests/` — 191 assertions, all passing:
  - JSON codec: round-trips, Arabic/Hebrew `\uXXXX` escapes, surrogate pairs,
    malformed-input rejection, deterministic (sorted-key) encoding
  - spec: defaults, validation error codes, inch→mm conversion, null-disable
  - rules: golden panel numbers for 900×720×560/t18/grooved-9
  - hardware: pin ladder counts/positions/pitch, Cabineo counts/positions,
    disable paths
  - geometry: part merging, labels, deterministic layout, no bbox overlaps
  - dxf: R12 structure, layer table, entity counts, closed polylines
  - bom: trilingual CSV, UTF-8 BOM, CRLF
- `gadget/main.lua` — CLI runner producing DXF + SVG + BOM + job.json
- CI: `gadget` job in `.github/workflows/ci.yml` (Lua 5.4 unit tests +
  trilingual smoke run)
- Toolchain: Lua 5.4.6 built from source into `tools/lua/` (sandbox has no
  apt access); compiled with `-DLUA_USE_POSIX` for `io.popen`

**Demo output** (`gadget/out/euro-base-900*`): 5 unique parts, 7 total,
3.356 m², ~2 sheets — matches the hand-computed golden numbers.

**Bugs found & fixed during the build:**

1. `in` is a Lua keyword — `UNIT_SCALE = { in = ... }` broke the parser;
   now `["in"]`.
2. JSON number pattern rejected single-digit integers (`1` failed, `42`
   passed only by backtracking luck) — fixed pattern to `^-?%d+%.?%d*`.
3. `(...)` is empty in `dofile`'d chunks — tests now use a `T_DIR` global.
4. Bare Lua compile lacked `io.popen` — recompiled with `-DLUA_USE_POSIX`.

**Decisions recorded:**

- DXF dialect: R12 ASCII (AC1009) — maximum portability (VCarve, Aspire,
  ArtCAM 2018 all read it). No `$INSUNITS` (post-R2000 feature).
- Merged side panels share one feature set (rectangles are mirror-symmetric;
  the mirror flag stays in metadata for assembly docs).
- `job.json` is the official bridge format to `dxfnest` (the nesting
  optimizer in this repo) — the future Nesting Companion paid pack.
- BOM CSV always UTF-8 + BOM + CRLF → opens correctly in Excel on Windows
  for Arabic/Hebrew.

**Known v0.1 simplifications** (documented in `gadget/README.md`): full-height
back groove (corner logic in v0.2), single shelf zone, mm-only BOM output.

**Next (v0.2):** zones (shelf rows / drawer stacks), door & drawer fronts
with reveal math, hinge + slide placement from the existing library data,
groove drawing on side panels. In parallel: owner purchases VCarve Pro →
SDK study → first gadget-shell spike.

---

## v0.7.0 — 3D viewer, dimension check, import (2026-09-23)

**User directive:** "UPGRADE THE APP TO BE MORE USER FRIENDLY, TO BE SHOWN
3D VIEW, EXPLODE MODE, ETC... GET CONFIGURATION FROM OTHER APP AND DO. AND
ALSO CHECK THE DIMENSION."

Four new core modules (all headless, all tested):

- **`model3d.lua`** — builds a 3D box model from the decomposed panels:
  sides/bottom/top/back/divider/shelves/doors/drawer fronts/drawer boxes,
  each with a center, size, role color and an *explode vector* (sides ±x,
  bottom −y, top +y, back +z, doors −1.35z, fronts −1.9z, drawer boxes a
  −(0.45+i·0.28)z staircase, shelves +0.35z). `build_loose()` lays
  imported parts out flat on the floor.
- **`check.lua`** — dimension checker: part-vs-board (error / rotate info),
  zero-size guard, narrow/low doors, low drawer fronts, box taller than
  front opening, narrow boxes, hinge count per door height (info, from the
  hardware library), back groove > half panel, deep shelf setback.
  Emits `{level, code, params}` entries; main.lua prints them trilingually
  and stores them in job.json.
- **`viewer.lua`** — ONE self-contained HTML file: hand-written canvas 3D
  engine (painter's algorithm, depth-sorted quads), drag-rotate,
  wheel-zoom, front/iso/top buttons, explode slider 0–100, clickable parts
  list with dims/edge notes, colored checks panel. No internet, no
  libraries — opens offline in any browser.
- **`importer.lua`** — `from_foreign(raw, map)` converts other apps' JSON
  configs through **map files** (`importers/*.json`: field aliases, unit
  values, defaults); `parse_cutlist_csv()` accepts cut-list CSVs with
  EN/HE/AR headers and quoted materials; `loose_panels()` feeds imported
  parts through the normal pipeline.

New CLI: **`convert.lua`** (foreign JSON or CSV → Najjar spec → main.lua).
main.lua grew a loose-parts mode, the dimension check and the viewer
output; job.json now carries the check entries. The VCarve shell preloads
the four new modules and writes `najjar_viewer.html` + check summary next
to the BOM/DXF in the gadget `out/` folder.

**Bugs found & fixed this round:** lang JSON corruption from the key
insertion (trailing/missing commas, unescaped `"` in Hebrew — switched to
״ gershayim), `gsub` returning two values into `tonumber` in the importer,
Hebrew CSV width alias wrong (`לוח רוחב` → `רוחב`), single-cabinet import
path warning spuriously, shelf rows with qty > 1 only rendering one shelf
in 3D. Also: `tools/` was fully gitignored — the build/package scripts
vanished on the sandbox re-clone; now only builds/reference clones are
ignored and the scripts are committed.

**664 assertions green on Lua 5.4.6 and 5.5.1** (545 → 664). Golden numbers
for the v0.1–v0.6 pipeline unchanged and still asserted. Roadmap: v0.8 =
shell hardening (live VCarve first-run), v0.9 = licensing + website.

---

## v0.8.0 — nesting, cost, plinth, hardening (2026-09-23)

**User directive:** "need more work to be better also try do a fixising — you
need to do a lot of thing to be a professional plugins."

Professional-gap round — the four things a shop actually asks for:

- **`nest.lua`** — real sheet packing (the repo is named nesting-optimizer,
  so far we only *estimated* sheets by area): deterministic shelf-packing,
  kerf + trim margins, grain-aware rotation rules (doors/fronts/plinths
  never rotate), per-sheet SVG reports with labels, dims and grain arrows,
  utilization % into console + job.json. Kitchen-job golden: 5 sheets at
  75% (the old area estimate claimed 4 — now honest).
- **`cost.lua`** — quote per job: boards (nested count x price/m2) + edge
  metres (from parts' edge_banding meta) + counted hardware (hinges by door
  height from the library table, pins 4/shelf, connectors per panel layout,
  slides per drawer box, LED channel per metre). Prices live in user data:
  `pricing` spec block + `price` fields in the hardware JSONs (placeholders
  until the shop sets real numbers). Appended to the BOM CSV.
- **plinth/toe-kick** — `construction.plinth = {height, recess, thickness}`;
  euro model: the strip mounts UNDER the unchanged body (sides stay full
  height — no golden drift), own part + BOM recess note, 3D body lifted,
  plinth explodes downward. `templates/base-plinth.json` demo.
- **fixising** — `from_foreign` nil-map crash; LED channel missing from the
  cost list; first-sheet bootstrap bug (everything "unplaced"); semicolon/
  tab CSV delimiters + decimal commas; JSON depth bomb (limit 200, clean
  error); viewer touch (rotate + pinch) for shop tablets; i18n parity test
  (every key in EN+HE+AR, forever); fuzz suite over spec/JSON/CSV.

**1246 assertions green on Lua 5.4.6 + 5.5.1** (664 → 1246). CHANGELOG.md
added (keep-a-changelog format). Hardware JSONs now carry editable
placeholder prices. Roadmap: v0.9 = shell hardening (live VCarve first-run
when the license arrives), v1.0 = licensing + website.

---

## v0.9.0 — shell hardening: full wizard + one-click toolpaths (2026-09-23)

**User directive:** "do it" (continue the announced v0.9 shell-hardening
round).

- Re-cloned the public gadget references (sandbox reset had wiped
  tools/_gadgets-tm) and **verified the toolpath API from real source**:
  `ToolpathManager()` global, `:LoadToolpathTemplate(path)` (rebuilds a
  toolpath from a `.ToolpathTemplate` file; prompts "apply to all
  sheets?" which the API cannot suppress — documented, answer No),
  `:SaveToolpathAsTemplate`, list iteration via GetHeadPosition/GetNext.
- **Three-page wizard** (sequential HTML_Dialogs, step x of 3 in the
  title): every v0.7/v0.8 configuration is now user-enterable inside
  VCarve — drawer zone (250 mm/drawer, auto-capped at H-150, refitted
  count), plinth, board size, kerf, margin, all three prices + currency.
  Pages/fields are data (NajjarShell.PAGES); READ_IDS derives from them,
  so the headless consistency test covers every id automatically.
- **Toolpath template loader**: `NajjarShell.load_toolpath_templates` —
  fixed filenames per the 11-layer machining contract, io.open existence
  check, pcall'd LoadToolpathTemplate, loaded/failed lists; final message
  reports what loaded (or how to set it up). `toolpaths/README.md`
  documents the owner's one-time 10-minute setup.
- assemble_spec: drawers+doors / drawers+open-with-shelves / legacy plain
  paths; currency sanitized to A-Z (digits snuck through the first
  version — test caught it).
- Tests: page/id consistency (per page + flattened), full wizard spec
  through the real pipeline (plinth/doors/fronts/drawer boxes/nest/cost,
  JOD currency end-to-end), drawer cap, template loader with fake
  manager (success/failure/empty-dir). **1365 assertions green on
  Lua 5.4.6 + 5.5.1** (1246 → 1365).

Roadmap: v1.0 = live VCarve first-run when the license arrives, licensing
+ website after.

---

## v0.10.0 — board-ready VCarve drawing + self-check (2026-09-23)

**User directive:** "upgrade the app first to be fully with VCarve Pro,
before starting licensing."

Goal: the deepest real-VCarve integration possible without a live license.

- Investigated `SheetManager` in the verified public gadgets: only
  read-side usage (ActiveSheetId, sheet lists for toolpath reordering) —
  no verified sheet-creation call, so the safe route is drawing boards
  side by side with boundaries, not gambling on an unverified API.
- **`vectric.render_sheets`** — draws the nesting result through any
  backend: per board a CNC_BOUNDARY rectangle + INFO board label; per
  placement the outline at the packed position, features transformed
  (90° CW in-plane rotation: `(x,y) -> (px + part.h − y, py + x)`, face
  never mirrored), ETCH part label above each rect; boards offset by
  width + 100 mm gap. Works against the mock (tests) and the real
  backend unchanged (same 4-method contract).
- **Wizard switch** `Output.SheetMode` (page 3, default on): on = the
  job becomes the cut file; off = classic per-part layout for editing.
- **`NajjarShell.self_check(env)`** — REQUIRED_API (VectricJob,
  HTML_Dialog, DisplayMessageBox, Contour, Point2D, CreateCadContour) +
  OPTIONAL_API (ToolpathManager); main() warns once with the missing
  list instead of failing mysteriously on the first live run.
- Tests: exact-coordinate cases (straight + rotated placement transforms,
  sheet offsets, label positions), empty-nesting guard, kitchen-job
  golden end-to-end (38 outlines, every feature on every instance,
  5 boundaries, 43 labels — counts derived from the parts themselves),
  self-check with full/old/nil environments. **1400 assertions green on
  Lua 5.4.6 + 5.5.1** (1365 → 1400).

Next per the owner's directive: **licensing** (offline keys, trial mode)
after the live VCarve first-run.
