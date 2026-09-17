# Installation

## Requirements

* Python **3.10, 3.11 or 3.12**
* A working CPython (PyPy is not tested)
* No compiled dependencies — pure Python wheels (ezdxf, Shapely, NumPy, Matplotlib)

## Install from source (recommended while pre-1.0)

```bash
git clone https://github.com/Izz-Badarin/dxf-nesting-optimizer.git
cd dxf-nesting-optimizer
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -e .
```

This installs the `dxfnest` command and the `nesting` Python package.

## Development install

```bash
pip install -e ".[dev]"
```

Adds `pytest`, `pytest-cov`, `ruff` and `mypy`.

## Verify

```bash
dxfnest --version
dxfnest info examples/inputs/furniture_parts.dxf
```

## Dependencies

| Package | Purpose |
|---|---|
| [ezdxf](https://ezdxf.readthedocs.io/) | DXF reading/writing, entity paths, block explosion, recover mode |
| [Shapely](https://shapely.readthedocs.io/) | polygon geometry: area, containment, buffering, transforms |
| NumPy | numeric support for Matplotlib / future NFP math |
| Matplotlib | PDF sheet visualization and reports |

## Troubleshooting

* **` externally-managed-environment`** (Debian/Ubuntu) — always use a venv as
  shown above.
* **Damaged DXF files** — the importer automatically falls back to ezdxf's
  `recover` mode and reports what it fixed.
