# Toolpath templates — one-click toolpaths for Najjar Pro

Najjar Pro draws every machining operation on its own **layer**. If you save
one toolpath template per layer into this folder, the gadget loads them
automatically after drawing — the toolpaths appear in the toolpath list,
ready to preview and post. No template drawing or re-selection by hand.

## How to set it up (once, ~10 minutes)

1. Run the gadget once (or draw any cabinet) so the layers exist in a job.
2. In VCarve / Aspire create a toolpath for one layer
   (e.g. select the `CUT` layer vectors → Profile Toolpath → your tool,
   18 mm depth, outside offset, tabs to taste).
3. On the Toolpaths tab: **Save Template As…** — name it exactly
   `CUT.ToolpathTemplate` and save it into **this folder**.
4. Repeat for each layer you actually use:

   | File                        | Operation                                  |
   |-----------------------------|--------------------------------------------|
   | `CUT.ToolpathTemplate`      | profile cut, part outlines (through)       |
   | `DRILL5_SHELF.ToolpathTemplate` | Ø5 shelf pin rows (face A)             |
   | `DRILL5_SHELF_FLIP.ToolpathTemplate` | Ø5 shelf pin rows (flip layer)   |
   | `DRILL_CABINEO.ToolpathTemplate`   | Ø5 Cabineo drill (through)           |
   | `POCKET_CABINEO.ToolpathTemplate`  | Ø15 Cabineo pocket, 11 mm deep        |
   | `DRILL_HINGE.ToolpathTemplate`     | Ø35 hinge cups (12.8 deep) + Ø5.5    |
   | `DRILL_SLIDE.ToolpathTemplate`     | drawer slide locking pattern          |
   | `LED_GROOVE.ToolpathTemplate`      | 8 mm LED channel groove                |
   | `BOX_GROOVE.ToolpathTemplate`      | drawer bottom groove                    |
   | `DRILL_DOWEL.ToolpathTemplate`     | drawer box dowel/rafix holes            |
   | `ETCH.ToolpathTemplate`            | V-bit part labels                        |

5. Run the gadget again — the final message lists every template that
   loaded. Done: draw → toolpaths → post.

## Notes

- When VCarve asks *"apply the template to all sheets?"* answer **No**
  (this is a Vectric prompt the API cannot suppress).
- Layers without a template file are simply skipped — start with just
  `CUT` and add the rest when you are ready.
- Templates are per-tool settings; they live in this folder next to the
  gadget, so they survive gadget updates (the installer keeps user files).
