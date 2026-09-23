# Najjar Pro — TEST CARD (about 10 minutes)

Everything here runs **free** on your shop PC. No VCarve, no license needed.
If anything below does not match, send a screenshot + one sentence.

---

## 1. One-time: get Lua (a tiny free program)

1. Download from **https://sourceforge.net/projects/luabinaries/files/**
   → `5.5` → `Windows x64` → `lua_5.5.1_Win64_bin.zip`
2. Copy **lua55.exe** (and its `.dll` file) into **this folder**

(Any Lua 5.3 / 5.4 / 5.5 works the same.)

## 2. Run the demo (2 minutes)

Double-click **`run-demo.bat`**

Expected:
- the test run ends with **`1400 passed, 0 failed`**
- your browser opens the **3D viewer** → drag to rotate, scroll to zoom,
  pull the **Explode** slider, click parts in the list, read the
  dimension-check panel
- a **nesting board** SVG opens → the boards exactly as the machine
  will cut them (labels, sizes, grain arrows)

## 3. YOUR cabinet (5 minutes)

Open **`templates\MY-CABINET.json`** in Notepad and set your real cabinet
(width / height / depth, shelves, doors, drawers). Then open a command
prompt in this folder and run:

```
lua55 main.lua templates\MY-CABINET.json out ar
```

Check the **`out\`** folder:
- `MY-CABINET_bom.csv` → open in Excel: part sizes, edge banding,
  **cost estimate at the bottom**
- `MY-CABINET_nesting_1.svg` (and 2, 3...) → boards ready to cut
- `MY-CABINET_viewer.html` → 3D view, explode, dimension check
- the console shows `Estimated cost: ...`

## 4. Import test (optional, 2 minutes)

Have a cut list from another program (CSV)? Put it in this folder and run:

```
lua55 convert.lua your-list.csv my-job.json
lua55 main.lua my-job.json out ar
```

(English, Hebrew or Arabic headers all work.)

## 5. Inside VCarve Pro (only when you have a license)

1. VCarve → **Gadgets → Install New Gadget…** → pick
   **`NajjarPro.vgadget`** (it is in this folder)
2. Restart VCarve → **Gadgets → Najjar Pro**
3. Fill the three wizard pages → **OK**
   → the nested boards appear in the job, each operation on its layer,
   ready for toolpath templates and post.
   A first-run check will tell us immediately if anything is missing.

---

## What to send back after testing

For every item above: **works** / **wrong** — plus a screenshot and one
sentence ("the shelf should be 500 not 490, because ...").
In Arabic, Hebrew or English — whatever is easiest.

Then we plan the next upgrade together.
