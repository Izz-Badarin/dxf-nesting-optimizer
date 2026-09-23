# Parametric Cabinet Builder for ArtCAM 2018 — Work Plan

> A local version of the "Smart Cabinet Builder" idea (Klemar CNC's system for
> VCarve), adapted to an **ArtCAM 2018** workflow and integrated into the
> existing `dxf-nesting-optimizer` pipeline.
> Planning document only — no code written yet.

---

## 1. Decoding: what the Klemar system actually does

The Klemar post describes a **parametric cabinet generator** running inside
VCarve Pro — almost certainly as a Vectric Gadget (Vectric's official Lua
plugin format). Behind the marketing, there are four fairly simple
engineering components:

| Marketing promise | What it means engineering-wise |
|---|---|
| "You define dimensions – the system handles the rest" | A construction-rules engine: W×H×D + material thickness decomposes into a dimensioned panel list (sides, bottom, top, back, shelves, dividers) |
| "Shelves and partitions by area" | A zone model — splitting the front and interior into cells with height/width rules |
| "Doors and drawer fronts" | An overlay/gap calculator (full overlay, inset, 3 mm reveal) deriving fronts from the geometry |
| "Shelf holes, slides and hinges" + "Cabineo connections" | A **hardware library**: ready-made drilling patterns per item, auto-placed by system-32 rules |
| "Cabinet marks" + "LED strip prep" | Marking/groove layers that get a separate toolpath in CAM |
| "Dimensions and info for every part" + "tidy export" | BOM + labels + structured, layer-based DXF export |

**Key insight:** the "magic" is not the drawing — it is **encoding the
carpenter's knowledge** (rebates, back grooves, hinge positions, drilling
patterns) as declarative rules + a data-driven hardware library. That is
exactly what we can build for an ArtCAM environment too.

---

## 2. Reality check: ArtCAM 2018 vs VCarve

| | VCarve Pro (Klemar) | ArtCAM 2018 (us) |
|---|---|---|
| Official plugins | Yes — Gadget SDK (Lua) | **None** — no SDK, no supported public API |
| Product status | Supported | **EOL** — Autodesk discontinued ArtCAM in 2018; the commercial successor is Carveco |
| Vector import | Native DXF | DXF via the *Autodesk Manufacturing Data Exchange Utility* (ships with the installer; if missing — import fails) |
| Layers on import | Yes | **Yes** — Vector Import → Destination: *Preserve Layers* (2017+) |
| Drilling | via toolpath | via toolpath (Drill / Pocket) per layer |

**Architectural conclusion:** we do not build a plugin *inside* ArtCAM
(impossible), and we don't need to. We build an **external engine** that
emits machine-ready DXF files with a fixed layer convention; ArtCAM is used
only as the toolpath stage: import with *Preserve Layers*, then run a saved
toolpath template per layer (cut / drill 5 / drill 8 / hinge cup 35 / engrave).

**Strategic bonus:** DXF is neutral — the same engine will later work against
Carveco, VCarve, or any other CAM, unchanged. We are not chaining ourselves
 to dead software.

---

## 3. What we already have and where this fits

This repo is precisely the stage *after* a generator: `dxfnest` already
imports DXF, nests with two strategies, exports CNC-ready sheets with the
`CUT / ETCH / OFFCUT / CNC_BOUNDARY / INFO` layers, and produces reports +
PDF + web GUI. The README even states the spacing model is taken from
ArtCAM 2018. The parametric generator is **the missing link before the
nester**:

```
 spec.json  (dimensions + zones + hardware)
      │
      ▼
┌──────────────────────────┐
│  cabinets engine (new)   │   construction rules + hardware library
└──────────────────────────┘
      │
      ├─► per-part DXF (CUT/DRILL_*/ETCH layers) ──► ArtCAM 2018 ──► toolpaths
      ├─► BOM.csv · cabinet-mark list · setup-sheet PDF
      ▼
 nesting engine (existing) ──► nested sheet DXFs ──► ArtCAM 2018 (one import per sheet)
```

---

## 4. Proposed architecture

A new package `src/cabinets/` that emits the repository's existing `Part`
objects directly (leveraging `nesting.geometry.part` + the metadata support
that is already there), so parts flow into nesting **without a wasted DXF
round-trip**:

| New module | Responsibility |
|---|---|
| `cabinets/spec.py` | dataclasses + spec loading/validation (JSON/YAML): dimensions, materials, zones, hardware |
| `cabinets/rules.py` | geometric decomposition: sides/bottom/top/back/shelves/dividers/fronts, back groove, reveals |
| `cabinets/hardware/` | hardware library **as data files** (not code!): drilling patterns per model, default placements |
| `cabinets/zones.py` | zone model: shelf rows / drawer stacks / door cells, height & width splitting |
| `cabinets/parts.py` | assembling each part → `Part` (outline + holes + metadata: name, size, cabinet mark, grain direction) |
| `cabinets/export.py` | per-part DXF export (or one combined file), BOM.csv, cabinet-mark list, setup sheet |
| `cabinets/cli.py` | new command: `dxfnest cabinet spec.json -o out/ [--nest]` |

Principles carried over from the rest of the project: library-first, full
determinism (same input → same output, golden tests), validation with
warnings instead of silent failure.

### Panel "face convention" — a critical design point

Every part is exported in a **"face-up toward the machine"** layout: all
drilling for one face appears as circles on its layer. A part drilled on
both faces gets `*_FLIP` layers (second-face drilling) and the BOM marks it
for manual flipping — exactly the problem every cabinet shop solves in their
head today; here the system simply tells you what to flip and when.

---

## 5. Data model — example spec

```json
{
  "project": "kitchen-204",
  "panel_material": { "thickness": 18.0, "name": "ply-birch-18" },
  "cabinets": [
    {
      "id": "B1",
      "width": 900.0, "height": 720.0, "depth": 560.0,
      "construction": {
        "panel_layout": "top_bottom_between_sides",
        "back": { "type": "grooved", "thickness": 9.0,
                  "groove_depth": 8.0, "groove_offset": 10.0 }
      },
      "zones": [
        { "type": "shelf_row", "from": 0, "to": 460,
          "dividers": [{ "at": 450 }], "shelves": { "count": 2, "adjustable": true } },
        { "type": "drawers", "from": 460, "to": 720, "count": 3 }
      ],
      "fronts": { "style": "full_overlay", "reveal": 3.0 },
      "hardware": {
        "connector": "cabineo12",
        "shelf_pins": { "system": "32", "rows": ["front", "rear"] },
        "hinges": "cup35_th52",
        "slides": "undermount",
        "led_channel": "8x8_under_top"
      }
    }
  ]
}
```

Every numeric value is an overridable default — the engine adapts to your
way of working, not the other way round.

---

## 6. Hardware library — default values (to be verified against catalogs)

| Item | Library default | Notes |
|---|---|---|
| Shelf pins (system 32) | Ø5 drill, rows at 32 mm pitch, front column 37 mm from edge | depth/position parametric |
| Cabineo 12 (Lamello) | Ø5×12 hole + Ø15 pocket (manufacturer spec); minimum edge distance parametric | placement: bottom/top/fixed-shelf connections into the sides |
| Cabineo 8 (Lamello) | Ø8 face drill | numbers to verify against the catalog |
| Standard cup hinge | Ø35 cup, 12.8 depth, 52×5.5 pattern (Hettich data) | hinge count by door height: ≤900→2, 900–1600→3, then 4 (tunable) |
| Drawer slides | pattern by type (undermount / side-mount) — separate library entry | depends on the slide-type answer |
| LED channel | parametric groove (e.g. 8×8) under the top/shelf, with entry ramp | flexible placement |

Values live as data files under `cabinets/hardware/` — adding a new hardware
model will not require code changes.

---

## 7. Export layer convention & ArtCAM mapping

We extend the existing set (`CUT/ETCH/OFFCUT/CNC_BOUNDARY/INFO`) with
drilling layers. ASCII-only names (ArtCAM-safe), fixed color per layer:

| Layer | Content | Recommended ArtCAM operation |
|---|---|---|
| `CUT` | cut outlines + through holes | Profile toolpath with tool offset |
| `DRILL5_SHELF` | Ø5 shelf-pin holes | Drill 5 mm (peck) |
| `DRILL_CABINEO` | Cabineo drills (Ø5/Ø8 per model) | Drill by diameter |
| `POCKET_CABINEO` | Cabineo 12 pockets (Ø15) | Pocket / large drill |
| `DRILL_HINGE` | Ø35 cups + screw pattern | Drill 35 + 5.5 |
| `DRILL_SLIDE` | slide holes | Drill per library |
| `LED_GROOVE` | LED channel path | Pocket with ramp |
| `ETCH` | cabinet mark + part ID + sizes | V-bit engrave |
| existing layers | as today (OFFCUT, CNC_BOUNDARY, INFO) | — |

At the end of Phase 1 we run a **real import test in ArtCAM 2018** on your
machine (Preserve Layers; default DXF R12/R2018 ASCII) — and lock the final
file format to whatever opens cleanly.

---

## 8. Milestones

| Phase | Scope | Deliverable / exit criteria |
|---|---|---|
| **0 — Decisions** | answer the questions in §10, verify hardware specs against catalogs | spec locked |
| **1 — Basic-cabinet MVP** | spec → sides/bottom/top/back/shelves + dimensions + BOM + per-part DXF. CLI `dxfnest cabinet` | a 900×720×560 cabinet → 6 dimensioned parts; DXF opens cleanly in your ArtCAM 2018 |
| **2 — Zones & fronts** | zones, dividers, doors and drawer fronts with reveal math | a mixed cabinet (shelves+drawers+door) produced end-to-end |
| **3 — Hardware library** | system 32, Cabineo, hinges, slides — all drilling as layers | drilling patterns match the manufacturer catalog; golden geometry tests |
| **4 — Production integration** | parts flow straight into the nester; nested sheets with drilling layers; an ArtCAM toolpath how-to | `dxfnest cabinet --nest` → one sheet imported into ArtCAM with all layers |
| **5 — Extras** | LED, printed cabinet-mark list, saved cabinet templates, a tab in the web GUI, SketchUp export | by your priority order |

---

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| ArtCAM 2018 EOL — DXF import can be fragile (depends on installed Exchange Utility) | real import test already in Phase 1; R12 ASCII export option; no reliance on new DXF features |
| Hebrew text in DXF poorly supported by ArtCAM | engraved labels in English/transliteration; full info in Hebrew in the BOM/setup-sheet (PDF/CSV) |
| Wrong hardware specs = scrapped parts | every value flagged "to verify"; verify against manufacturer catalog in Phase 0; no drilling before sign-off |
| Two-sided drilled parts in nesting | face convention + `*_FLIP` layers + explicit flip instruction in the BOM |
| Options explosion (cabinet/hardware types) | declarative rules + data library; defined exit gate per phase |

---

## 10. Open decisions (blocking Phase 0)

1. **Box connections** — Cabineo 12 only? Cabineo 8? Or confirmat/minifix first?
2. **Back panel** — grooved (9 mm rebate), rear-nailed, or both as a parameter?
3. **Primary output for ArtCAM** — one DXF per part, one nested sheet via the
   nester, or both?
4. **Labels** — English engraving + Hebrew BOM, or something else?
5. **Drawer slides** — undermount or side-mount? (determines the drilling pattern)
6. **Materials** — 18 mm panels as the base? 9 mm back? (library defaults)

---

## 11. Sources gathered during planning

- ArtCAM 2018 — DXF import requires the Autodesk Manufacturing Data Exchange Utility 2018 (Autodesk forum).
- ArtCAM 2017+ — vector import with Destination: *Preserve Layers* (Autodesk support article).
- Lamello Cabineo 12 — Ø5×12 and Ø15 drilling, cutter Ø12 max (Colonial Saw / csaw.com).
- Hettich — hinges: Ø35 cup, 12.8 depth, 52×5.5 pattern (Hettich Hinges 2020 catalog).
- ArtCAM 2018 spacing/nesting model — already documented in this repo's README.
