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

## `dxfnest nest` — nest and export (milestone M3+)

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
| `--pdf` | off | render sheet layouts to PDF |
| `--report` | `both` | comparison report format (JSON / Markdown) |

### The spacing model

Following ArtCAM's proven scheme, the minimum outline-to-outline gap between
two parts is:

```
gap = tool_diameter + 2 × clearance
```

(half is charged to each part during collision tests), and parts keep
`edge_clearance` from the sheet boundary.

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
