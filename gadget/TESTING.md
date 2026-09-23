# Najjar Pro — How To Test (5 minutes, no VCarve needed)

This guide is for the shop computer. Everything is free — you do **not**
need VCarve, Aspire or any license to test the core.

---

## Step 1 — Get the files

On your shop PC, open GitHub in a browser:

1. Go to the repository: **Izz-Badarin/dxf-nesting-optimizer**
2. Click the branch button (it says `main` or a branch name) and select
   the branch **`arena/01a0cd18-dxf-nesting-optimizer`**
3. Click the green **`<> Code`** button → **Download ZIP**
4. Extract the ZIP (right-click → Extract All)

Direct link (if it works in your browser):

```
https://github.com/Izz-Badarin/dxf-nesting-optimizer/archive/refs/heads/arena/01a0cd18-dxf-nesting-optimizer.zip
```

Everything you need is inside the **`gadget/`** folder.

---

## Step 2 — Get Lua (one small free program)

Najjar Pro runs on **Lua** — a tiny, free programming language.

**Easiest way (no installation):**

1. Download `lua-5.4.x_Win64_bin.zip` from
   **https://sourceforge.net/projects/luabinaries/files/** (open the
   `5.4.x/` folder → `Windows Libraries` → `Win64` → the `..._bin.zip`)
2. Extract it
3. Copy **`lua54.exe`** (and `lua54.dll` if present) into the **`gadget`**
   folder — next to `main.lua`. Done!

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
1. Run all **423 automatic tests** (must end with `423 passed, 0 failed`)
2. Generate all 3 demo cabinets (base, wardrobe, kitchen)
3. Open the **previews in your browser**

To run a demo in **Arabic** or **Hebrew**, open a command prompt in the
`gadget` folder and type:

```
lua54 main.lua templates\kitchen-mixed.json out ar
lua54 main.lua templates\kitchen-mixed.json out he
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
lua54 main.lua templates\MY-CABINET.json out en
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

## Fastest option of all

Don't want to install anything yet? Just write me the cabinet's
dimensions and how you build it, and I will generate it here and show
you the results in the chat.
