"""dxf-nesting-optimizer: dual-strategy DXF nesting with comparative analysis."""

from ._version import __version__
from .analysis.compare import build_report
from .config import NestSettings, SheetSpec
from .geometry.part import Part
from .io.dxf_export import export_nesting_dxf
from .io.dxf_import import ImportResult, import_dxf
from .nesting.base import NestingResult, Placement, SheetLayout, Strategy
from .nesting.symmetry_first import SymmetryFirstStrategy
from .nesting.waste_first import WasteFirstStrategy

__all__ = [
    "ImportResult",
    "NestSettings",
    "NestingResult",
    "Part",
    "Placement",
    "SheetLayout",
    "SheetSpec",
    "Strategy",
    "SymmetryFirstStrategy",
    "WasteFirstStrategy",
    "__version__",
    "build_report",
    "export_nesting_dxf",
    "import_dxf",
]
