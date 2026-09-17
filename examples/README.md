# Example files

All files are generated deterministically by [`generate.py`](generate.py):

```bash
python examples/generate.py            # writes to examples/inputs/
```

## Inputs

| File | Contents | Demonstrates |
|---|---|---|
| `furniture_parts.dxf` | cabinet job: 4× `SIDE_PANEL` block inserts (with system holes + text), 6 shelves, 2 rounded-top doors, 4 drawer fronts, 2 kick plates | INSERT/block parts, holes from circles, text metadata, identical-part merging |
| `mixed_curved.dxf` | 2 rings, an L-bracket made of 6 loose lines, a capsule made of 2 lines + 2 arcs, 2 ellipses, a spline blob, a gear with 6 holes, a mirrored pair | chain stitching, curved entities, holes/islands, mirror pairs |
| `stress_many_parts.dxf` | 400 mixed parts (rects, circles, rounded rects), seeded | performance |

## Outputs (from milestone M3)

`nesting-output/` results of `dxfnest nest examples/inputs/furniture_parts.dxf`
will be committed under `examples/outputs/` once the nesting engine lands:
nested DXFs per strategy, PDF visualization and the comparison report.
