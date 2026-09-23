#!/bin/sh
# Package the Najjar Pro gadget into an installable .vgadget (a ZIP with a
# single root folder), exactly like Vectric distributes gadgets.
#
# Usage:  sh tools/package-gadget.sh
# Output: gadget/release/NajjarPro.vgadget
#         (install in VCarve/Aspire via Gadgets -> Install New Gadget)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GADGET="$ROOT/gadget"
STAGE="$(mktemp -d)"
OUT="$ROOT/gadget/release"
mkdir -p "$OUT"

# single root folder named after the gadget
PKG="$STAGE/NajjarPro"
mkdir -p "$PKG/src/najjar" "$PKG/hardware" "$PKG/lang" "$PKG/importers"

cp "$GADGET/vcarve/"*.lua "$PKG/"
cp "$GADGET/src/najjar/"*.lua "$PKG/src/najjar/"
cp "$GADGET/hardware/"*.json "$PKG/hardware/"
cp "$GADGET/importers/"*.json "$PKG/importers/"
cp "$GADGET/lang/"*.json "$PKG/lang/"

# zip the folder so the archive root contains NajjarPro/
( cd "$STAGE" && zip -r -q "$OUT/NajjarPro.vgadget" NajjarPro )

echo "packaged: $OUT/NajjarPro.vgadget"
unzip -l "$OUT/NajjarPro.vgadget" | tail -3
