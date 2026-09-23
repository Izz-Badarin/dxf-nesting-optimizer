# Najjar Pro — gadget core (v0.4.0)

> **Every shop has a carpenter. Now it has Najjar Pro.**
> كُلّ ورشة عندها نجّار — هلق كمان عندها Najjar Pro

The headless Lua core of the **Najjar Pro** parametric cabinet builder —
the product planned in [`docs/vcarve-gadget-product-plan.md`](../docs/vcarve-gadget-product-plan.md).
**👉 New here? Read [`TESTING.md`](TESTING.md) — test everything on your
shop PC in 5 minutes, no VCarve needed.**

This code runs **without VCarve installed**; the thin Vectric API layer
(dialogs + drawing into a job) plugs on top once development licenses
arrive.

## What it does (v0.3)

You describe cabinets as **data** — and the shop's own configuration is
data too:

```json
{ "project": "kitchen-mixed",
  "units": "mm",
  "panel_material": { "thickness": 18.0, "name": "ply-18" },
  "sheet": { "width": 1220, "height": 2440 },
  "materials": { "shelf": { "thickness": 16.0, "name": "ply-16" } },
  "fronts": { "style": "full_overlay", "reveal": 3.0, "edge": 2.0 },
  "cabinets": [{
    "id": "K1", "width": 900, "height": 900, "depth": 550,
    "construction": { "back": { "type": "grooved", "thickness": 9 } },
    "zones": [
      { "type": "door", "from": 0, "to": 700, "doors": { "count": 2 },
        "dividers": [{ "at": 300 }],
        "shelves": { "count": 2, "adjustable": true } },
      { "type": "drawers", "from": 700, "to": 900,
        "drawers": { "count": 2, "box": true } }
    ],
    "hardware": { "connector": "cabineo_12", "shelf_pins": "shelf_pin_5",
                  "hinges": "hinge_cup_35", "led_channel": "led_channel_8x8" } }] }
```

and the core produces, fully dimensioned and deterministic:

- **Panels**: sides, bottom, top, grooved/nailed back — thickness and
  material **per role** (side/bottom/top/shelf/divider/door/front/drawer)
- **Classic euro construction**: with a grooved back, bottom/top/dividers
  are pulled forward of the back zone so the full-height back rides the
  side grooves
- **Zones**: `open` / `door` / `drawers` — per-zone shelves, door counts,
  drawer counts
- **Dividers** inside zones: per-bay shelf pieces, connector machining on
  the divider AND on the horizontal panels at the divider line; bays and
  connections computed automatically; `field-connect` notes where a
  divider meets no panel
- **Drawer boxes** (`"box": true`): sides, front/back, bottom — height,
  clearance, depth and bottom thickness all parametric; bottom joinery
  `"lay-in"` (default) or `"grooved"` (BOX_GROOVE machining on sides+FB,
  bottom sized into the grooves)
- **Drawer slide locking patterns** from the hardware library
  (`"slides": "slide_undermount"`): rear hole + front slot on the box
  sides, brand positions parametric; side-mount slides are screw-on (no
  machining) and the library says so
- **Divider pin columns**: dividers in adjustable-shelf zones get the
  system-32 ladder on BOTH faces — face B is pre-mirrored onto the
  `DRILL5_SHELF_FLIP` layer with a flip note (flip about the short axis)
- **Doors & drawer fronts** with full-overlay reveal math; doors carry
  their hinge side
- **System-32 shelf pin ladders** (2 columns, 32 mm pitch)
- **Cabineo 12 connector machining** (Ø15 pocket + Ø5 drill) on sides,
  dividers and horizontal panels — all from library data
- **Cup hinge placement** on doors (Ø35 + Ø5.5 pattern, count by height,
  mirrored pairs)
- **LED channel groove** on the top panel underside (flip note in the BOM)
- **BOM** (CSV, UTF-8 + BOM, EN/HE/AR, **mm or inch display**)
- **DXF R12** with one layer per machining operation
- **SVG preview** for humans
- **job.json** — the structured bridge to the nesting optimizer in this repo

### The shop's own baseline: `defaults.json`

Copy `defaults.json.example` to `defaults.json` next to `main.lua` and put
your shop's standard there — panel thickness & material, sheet/board size,
front reveals. **Every spec is merged over it** (the spec wins), so a
4-line spec inherits your whole shop configuration. `defaults.json` is
gitignored; each machine keeps its own.

## Run it

Requires any Lua 5.1+ (Lua 5.4 recommended). No other dependencies.

```bash
cd gadget
lua main.lua templates/kitchen-mixed.json out en      # English
lua main.lua templates/wardrobe-zones.json out ar     # العربية
lua main.lua templates/euro-base-900.json out he      # עברית
```

(No Lua installed? `sh ../tools/build-lua.sh` builds one in ~10 seconds.)

Outputs land in `out/`: `_parts.dxf`, `_preview.svg`, `_bom.csv`, `_job.json`.
Units: set `"units": "in"` and every input is read in inches; the BOM
displays inches too.

## Run the tests

```bash
cd gadget
lua tests/run_tests.lua     # 423 assertions
```

## Layout

```
src/najjar/         the core (pure Lua, no VCarve needed)
  json.lua            JSON codec (deterministic, \uXXXX -> UTF-8)
  merge.lua           deep merge powering defaults.json
  i18n.lua            EN/HE/AR translations, RTL flags
  spec.lua            spec defaults + validation (zones, dividers, boxes,
                      materials, fronts, sheet, hardware refs)
  rules.lua           construction rules -> dimensioned panels
  hardware.lua        data-driven drilling/groove placement
  geometry.lua        panels -> unique parts + layout + sheet estimate
  bom.lua             bill of materials -> CSV (Excel-safe, mm/in)
  dxf.lua             DXF R12 writer (POLYLINE/CIRCLE/TEXT per layer)
  svg.lua             styled preview
  layers.lua          the layer contract (name -> CAM operation)
  fs.lua              tiny file helpers (replaced by gadget SDK later)
hardware/*.json     HARDWARE LIBRARY — edit these, not the code
lang/*.json         UI strings EN / HE / AR — community translations welcome
templates/*.json    example specs: euro base, zoned wardrobe, mixed kitchen
defaults.json.example  copy to defaults.json for your shop baseline
tests/              unit tests + three golden fixtures
tools/              dev tooling (build-lua.sh builds a standalone Lua)
```

## The layer contract

| Layer | CAM operation |
|---|---|
| `CUT` | profile cut (tool offset on) |
| `DRILL5_SHELF` | drill Ø5 (shelf pins) |
| `DRILL_CABINEO` | drill Ø5 (connector) |
| `POCKET_CABINEO` | pocket Ø15 (connector) |
| `DRILL_HINGE` | drill Ø35 cup + Ø5.5 screws |
| `LED_GROOVE` | pocket the LED channel (top is flipped — see BOM) |
| `DRILL_SLIDE` | drill the slide locking pattern (hole + slot) |
| `DRILL5_SHELF_FLIP` | shelf pins for the opposite face (flip the part) |
| `BOX_GROOVE` | pocket the drawer-bottom groove (grooved boxes) |
| `ETCH` | V-bit engrave (labels, cabinet marks) |

## Golden references (asserted in tests)

**1) Euro base 900×720×560, t18, grooved back, 2 shelves** — 5 unique
parts: sides 560×720, bottom/top 864×541, back 880×720, shelves 862×550;
40 pins + 8 Cabineo features per side; 3.32 m².

**2) Wardrobe 1000×2000×550, door zone + drawer zone** — 8 unique parts
/ 14 total: doors 496.5×1596 with 3 hinges each (mirrored), fronts
996×130, shelves t16; 120 pins per side; 9.23 m².

**3) Kitchen-mixed 900×900×550, divider at 300 + boxes + slides + LED** —
13 unique parts / 24 total: divider 531×682 standing ON the bottom panel
(84 machining ops: 40 pins + 40 flip pins + 4 Cabineo; bottom panel drilled
at the divider line), per-bay shelves 289/553 wide, drawer boxes with
undermount locking (rear Ø10 + front slot per side), LED groove on the
flipped top; 6.17 m² → 3 sheets.

## ⚠ Verify before cutting

Hardware dimensions are **engineering defaults pending catalog sign-off**
(see the `"verify"` field in every `hardware/*.json`). Hinge cup inset
(22 mm), end margin (100 mm), drawer-box clearances (13 mm/side) and the
LED channel position are parametric — set them to your brands' values.
**No production cutting until a real part has been test-machined and
signed off.**

## Known simplifications

- Slide locking positions are generic defaults — set them to your brand
  (Blum / Hettich / generic) in `hardware/slide_undermount.json`.
- Drawer-box corner joinery (dowels / rafix) arrives in v0.5.
- Back groove corner geometry is the classic full-height method.

## Roadmap

v0.5 box corner joinery + VCarve gadget shell (dialogs, drawing, toolpath
templates) → v0.6 licensing + website.
See the product plan for milestones and business model.
