# Najjar Pro — How To Test (5 minutes, no VCarve needed)

This guide is for the shop computer. Everything is free — you do **not**
need VCarve, Aspire or any license to test the core.

---

## Step 1 — Get the files (one download)

In a browser, go to the repository **Izz-Badarin/dxf-nesting-optimizer**
(branch `arena/01a0cd18-dxf-nesting-optimizer`), then open
**`gadget` → `release`** and download:

**`NajjarPro-0.10.0-test.zip`**

Right-click the downloaded file → **Extract All** → open the folder and
read **`START-HERE.md`** (the 10-minute test card).

Everything is inside that one zip: the full core, the test suite, the
demo, your `MY-CABINET.json` worksheet, and `NajjarPro.vgadget` for the
VCarve step later.

(The fallback way still works: green `<> Code` button → Download ZIP →
everything is in the `gadget/` folder.)

---

## Step 2 — Get Lua (one small free program)

Najjar Pro runs on **Lua** — a tiny, free programming language.
**Lua 5.3, 5.4 and 5.5 all work** (the whole test suite is verified on
5.4 and 5.5).

**Easiest way (no installation):**

1. Download the `*_bin.zip` for **5.5.x or 5.4.x** from
   **https://sourceforge.net/projects/luabinaries/files/** (open the
   version folder → `Windows Libraries` → `Win64` → the `..._bin.zip`)
2. Extract it
3. Copy **`lua55.exe` (or `lua54.exe`) and its matching `.dll` file**
   into the **`gadget`** folder — next to `main.lua`. Done!

(`run-demo.bat` finds Lua automatically — in the gadget folder or on
PATH, any of 5.3 / 5.4 / 5.5.)

**If you use Chocolatey or Scoop:**

```
choco install lua        (Chocolatey)
scoop install lua        (Scoop)
```

**Mac / Linux:** `brew install lua` or `sudo apt install lua5.4`

---

## Step 3 — Run it

Double-click **`run-demo.bat`** in the `gadget` folder.

It will:
1. Run all **1400 automatic tests** (must end with `1400 passed, 0 failed`)
2. Generate all 3 demo cabinets (base, wardrobe, kitchen)
3. Convert a **foreign demo config** through the importer
4. Open the **3D viewer and previews in your browser**

**Try the nesting sheets** (`kitchen-mixed_nesting_1.svg`, ...): every board
laid out with labels and dimensions — this is what goes to the saw.
Kerf and margins: `kerf` and `margin` inside the `sheet` block of your spec.

**Check the cost line** in the console and at the bottom of the BOM CSV:
boards + edge banding + hardware. Prices are placeholders — set yours in
the `pricing` block (see `defaults.json.example`) and in each
`hardware/*.json` (`price` field).

**Try the 3D viewer** (`kitchen-mixed_viewer.html`):
- drag to rotate, scroll to zoom
- pull the **Explode slider** — the cabinet comes apart
- works on **tablets/phones** too (drag with one finger, pinch to zoom)
- click parts in the list to see their sizes
- check the **dimension check panel** on the side

To run a demo in **Arabic** or **Hebrew**, open a command prompt in the
`gadget` folder and type (`lua55` or `lua54` — whatever you copied):

```
lua55 main.lua templates\kitchen-mixed.json out ar
lua55 main.lua templates\kitchen-mixed.json out he
```

---

## Step 4 — What to look at

In the `gadget\out\` folder, for every cabinet you get 4 files:

| File | Open with | What to check |
|---|---|---|
| `*_preview.svg` | Any browser (double-click) | Do the parts look right? Holes where you expect? |
| `*_bom.csv` | Excel (double-click) | Every dimension, quantity, hole count, notes. **Read it like a cut list** |
| `*_parts.dxf` | ArtCAM / VCarve / any CAD | Layers, circles, geometry |
| `*_job.json` | (ignore for now) | Machine data for the future nesting feature |

---

## Step 5 — Test the DXF in ArtCAM 2018 (you can do this TODAY)

You already own ArtCAM — use it to prove the whole workflow:

1. Open ArtCAM 2018 → create a new model (size bigger than the layout)
2. **File → Import → Vector Data** → choose `kitchen-mixed_parts.dxf`
3. In the import dialog set **Destination: Preserve Layers**
4. After import, check:
   - Layers exist: `CUT`, `DRILL5_SHELF`, `DRILL5_SHELF_FLIP`,
     `DRILL_CABINEO`, `POCKET_CABINEO`, `DRILL_HINGE`, `DRILL_SLIDE`,
     `LED_GROOVE`, `ETCH`
   - Circles are real circles
   - Measure with the dimension tool: pin holes are **32 mm apart**,
     first pin row **37 mm** from the panel edge
   - Everything is in millimeters

If that import works, you have proven the entire Najjar Pro → ArtCAM
pipeline. Take a screenshot!

---

## Step 6 — THE REAL TEST: your own cabinet

This is the most important test of all. Take **one real cabinet from
your shop** (a simple one you know by heart) and check the system
against reality:

1. Open **`templates\MY-CABINET.json`** in Notepad
2. Change the numbers to YOUR cabinet (every line has a `_help` note)
3. Save it and run:

```
lua55 main.lua templates\MY-CABINET.json out en
```

4. Open `out\MY-CABINET_bom.csv` in Excel and check against your
   knowledge:

**The checklist:**

- [ ] Side panel height = your cabinet height
- [ ] Bottom/top width = cabinet width − 2 × panel thickness
- [ ] Back panel size matches your groove method
- [ ] Shelf width and depth match how you cut them
- [ ] Pin hole rows: start position, spacing (32 mm), how far they run
- [ ] Cabineo/hinge positions match where you drill
- [ ] Door/drawer front sizes match your overlay gaps
- [ ] Materials and thicknesses correct

**Anything that does not match how YOU build = tell me.** That list
becomes the next version. This is exactly how the system learns your
way of working.

---

## How to report a problem

Send me (in any language — Arabic, Hebrew, English):

1. The `MY-CABINET.json` file you wrote
2. A screenshot of the BOM or the preview
3. One sentence: "this number should be X because ..."

---

## Step 6.5 — Import a config from another app

Have a cut list from another program? Convert it:

```
lua55 convert.lua cutlist.csv my-job.json
lua55 main.lua my-job.json out en
```

Or a JSON config from another generator — with a map file that lists
that app's field names:

```
lua55 convert.lua foreign.json my-job.json --map importers\generic_flat.json
lua55 main.lua my-job.json out en
```

CSV headers work in English, Hebrew or Arabic
(`width / רוחב / عرض`...). Send me any config that fails to convert and
I will add a map file for that app.

---

## Step 7 — Install inside VCarve / Aspire (when you have a license)

1. Download **`NajjarPro.vgadget`** from `gadget/release/` in the repository
2. In VCarve Pro / Aspire: **Gadgets → Install New Gadget…** → select it
3. Restart, then **Gadgets → Najjar Pro**
4. Fill the three wizard pages (Cabinet → Interior → Hardware & boards)
   ("Draw nested boards" is on by default — the job shows every board
   with its parts at the packed positions, ready to cut)
   and press OK — the cabinet should appear in the job, each operation on
   its own layer; BOM/DXF/nesting/3D viewer land in the gadget's `out/`

**One-click toolpaths (do once, ~10 min):** create a toolpath for a layer
(e.g. profile cut on `CUT`), then *Save Template As…*
`CUT.ToolpathTemplate` into the gadget's `toolpaths/` folder. Repeat per
layer. From then on every gadget run loads them automatically —
see `toolpaths/README.md`. When VCarve asks to apply templates to all
sheets, answer **No**.

If anything fails inside VCarve, note the exact error message (or
screenshot) — the gadget shows load errors in a message box.

---

## Fastest option of all

Don't want to install anything yet? Just write me the cabinet's
dimensions and how you build it, and I will generate it here and show
you the results in the chat.
