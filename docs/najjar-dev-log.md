# Najjar Pro — Development Log

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
