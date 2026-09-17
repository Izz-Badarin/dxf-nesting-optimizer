# Contributing to dxf-nesting-optimizer

Thanks for your interest in improving the project!

## Development setup

```bash
git clone https://github.com/Izz-Badarin/dxf-nesting-optimizer.git
cd dxf-nesting-optimizer
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
```

## Workflow

1. Fork / branch from `main`.
2. Make your change. Keep it focused — one logical change per PR.
3. Add or update tests. Bug fixes should come with a regression test.
4. Run the full check suite locally (must be green):

```bash
ruff format src tests examples   # formatting
ruff check src tests examples    # lint
mypy src                         # type check
pytest --cov=nesting             # tests
```

5. Open a pull request describing *what* and *why*.

## Commit messages

Conventional-commits style, milestone-prefixed while the project is young:

```
feat: M3 waste-first nesting engine with MaxRects + shelf heuristics
fix(dxf_import): handle MTEXT without insertion point
docs: document the comparison report schema
```

## Code guidelines

* Python 3.10+ (no 3.11-only syntax in `src/`).
* Every module gets a docstring explaining its role in the pipeline.
* Geometry code must be deterministic: stable sorts, no random without an
  explicit seed. Identical inputs must always produce identical outputs.
* Never silently drop geometry — anything the importer cannot interpret must
  produce a warning.
* Type hints on all public functions; the package ships `py.typed`.

## Project structure

See [docs/architecture.md](docs/architecture.md) for the module map and
milestone plan. New features should slot into the existing layers
(geometry / nesting / analysis / io) rather than bypassing them.

## License

By contributing you agree that your contributions are licensed under the
[MIT license](LICENSE).
