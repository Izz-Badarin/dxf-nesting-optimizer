"""dxf-nesting-optimizer: dual-strategy DXF nesting with comparative analysis."""

from .config import NestSettings, SheetSpec
from .geometry.part import Part
from .io.dxf_import import ImportResult, import_dxf
from .nesting.base import NestingResult, Placement, SheetLayout, Strategy

__version__ = "0.1.0"

__all__ = [
    "ImportResult",
    "NestSettings",
    "NestingResult",
    "Part",
    "Placement",
    "SheetLayout",
    "SheetSpec",
    "Strategy",
    "__version__",
    "import_dxf",
]
