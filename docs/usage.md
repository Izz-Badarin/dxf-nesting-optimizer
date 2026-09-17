# Usage

## `dxfnest info` — inspect a DXF job (available now)

```bash
dxfnest info <file.dxf> [--unit UNIT] [--json]
```

* `--unit` — override the source unit (`mm`, `in`, `ft`, …). Default: read from
  the DXF header variable `$INSUNITS`; a missing/zero value is assumed to be
  millimetres and reported as a warning.
* `--json` — machine-readable output (same data, structured).

Exit codes: `0` parts found, `1` no nestable parts found, `2` usage error.

## `dxfnest nest` — nest and export

```bash
dxfnest nest <file.dxf> [-o OUTDIR] [--strategy {symmetry,waste,both}]
               [--sheet WxH] [--tool-diameter MM] [--clearance MM]
               [--edge-clearance MM] [--rotation-step DEG]
               [--mirror|--no-mirror] [--pdf] [--report {json,md,both}]
```

| Option | Default | Meaning |
|---|---|---|
| `-o, --outdir` | `nesting-output/` | output directory |
| `--strategy` | `both` | which strategy (or both, for comparison) |
| `--sheet` | `1220x2440` | sheet size in mm |
| `--tool-diameter` | `6.0` | cutter diameter (kerf) |
| `--clearance` | `4.0` | extra material around each part |
| `--edge-clearance` | `10.0` | min distance part → sheet edge |
| `--rotation-step` | `90` | allowed rotation increment in degrees |
| `--mirror` / `--no-mirror` | on | allow mirrored placements |
| `--depth` | `2` | effort 1–5 (OptiNest-style calculation depth) |
| `--pdf` | off | render sheet layouts to PDF |
| `--report` | `both` | comparison report format (JSON / Markdown) |

Output tree for `dxfnest nest job.dxf -o out/ --pdf`:

```
out/
  job_symmetry-first.dxf     nested sheets, CNC-ready layers
  job_waste-first.dxf
  comparison_report.json     machine-readable (docs/report-schema.md)
  comparison_report.md       human-readable side-by-side + recommendation
  job_comparison.pdf         summary page + one page per unique sheet
```

Exit codes: `0` success, `1` no nestable parts / unplaced parts,
`2` usage error.

### The spacing model

Following ArtCAM's proven scheme, the minimum outline-to-outline gap between
two parts is:

```
gap = tool_diameter + 2 × clearance
```

(half is charged to each part during collision tests), and parts keep
`edge_clearance` from the sheet boundary.

## `dxfnest gui` — the web GUI

```bash
pip install -e ".[gui]"
dxfnest gui [--host 0.0.0.0] [--port 8000]
```

Drop a DXF or pick an example, tweak the tooling settings, and run both
strategies with one click. The result view shows summary cards, the full
metric comparison, the recommendation with rationale, side-by-side to-scale
sheet renderings (with part tooltips and labels) and download buttons for
the DXFs, reports and PDF.

## How parts are detected in a DXF

The importer applies these rules, in order:

1. **INSERT block references** — each block is a part; repeated inserts merge
   into a quantity. Block name becomes the part name.
2. **Closed contours** — closed polylines, circles, ellipses, splines, and
   open line/arc chains that can be stitched closed.
3. **Containment grouping** (even-odd rule) — a contour inside another contour
   on the same layer is a **hole**; a contour inside a hole is an **island**
   (its own part). This mirrors ArtCAM's "group inside and outside of shapes".
4. **Identical parts** — same layer, area, size (rotation-invariant) and vertex
   count merge into one part with a quantity.

TEXT/MTEXT falling inside a part outline is attached as part metadata.
Anything that cannot become a closed contour is reported as a warning —
nothing is dropped silently.

## Using the library

```python
from nesting import NestSettings, import_dxf

result = import_dxf("job.dxf", NestSettings(tool_diameter=6.0))
for part in result.parts:
    print(part.part_id, part.name, part.quantity, part.area, len(part.holes))
```
