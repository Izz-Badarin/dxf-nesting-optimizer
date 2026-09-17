# Metric definitions

All metrics are computed per strategy and reported side-by-side. Sheet area is
`width × height` (default 1220 × 2440 mm = 2,976,800 mm²).

## Material utilization

```
utilization % = (Σ placed part area) / (sheet count × sheet area) × 100
```

Part area is the **true polygon area** (outline minus holes), not the bounding
box. Utilization is also reported **gross of kerf**: the cut-out area actually
consumed includes the kerf gaps, so gross utilization ≥ net utilization.

## Waste

```
waste % = 100 − utilization %
```

Reported both net (pure part area) and gross (including kerf and edge margins).

## Sheet replication efficiency

Measures the ability to reproduce identical sheets when parts repeat — the
numeric form of ArtCAM's "Sheet 1 (3 Copies)" merging.

Sheets are grouped by a placement signature (sorted list of part id, position,
rotation, mirror — rounded to 0.001 mm):

```
replication = Σ (group size − 1) / (sheet count − 1)
```

* `1.0` — every sheet is an exact repeat of the first (machine once, repeat N
  times), or a single-sheet job (trivially repeatable).
* `0.0` — no two sheets share a layout.

Also reported: number of unique sheet layouts and the copy count of each.

## CNC handling factors (M5)

| Factor | Definition |
|---|---|
| Clamping ease | minimum part-to-edge clearance; connectivity of the remaining waste skeleton (is the sheet still rigid mid-cut?) |
| Cutting path simplicity | total cut length, pierce/contour count, rapid-travel estimate, direction-change count, common-line cutting opportunities |

## Recommendation logic (M5)

A weighted score per strategy, weights configurable. Defaults favor the
waste-first strategy unless replication efficiency or clamping differs
materially — the report always shows the raw numbers and the rationale, so the
recommendation can be overridden by a human.
