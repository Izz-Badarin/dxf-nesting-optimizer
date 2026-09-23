#!/bin/sh
# Build the one-download test package for the shop PC.
# Output: gadget/release/NajjarPro-<version>-test.zip
#   (the whole runnable core + tests + templates + docs + the START-HERE
#    card + NajjarPro.vgadget for the VCarve step later)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GADGET="$ROOT/gadget"
OUT="$GADGET/release"
VERSION=$(grep -o 'VERSION = "[^"]*"' "$GADGET/src/najjar/version.lua" | cut -d'"' -f2)
STAGE="$(mktemp -d)"
PKG="$STAGE/NajjarPro-$VERSION-test"
mkdir -p "$PKG"

# the installable gadget travels inside the test zip
[ -f "$OUT/NajjarPro.vgadget" ] || sh "$ROOT/tools/package-gadget.sh"
cp "$OUT/NajjarPro.vgadget" "$PKG/"

# the runnable core + tests + templates + docs (no out/, no user defaults)
( cd "$GADGET" && cp -R START-HERE.md README.md TESTING.md CHANGELOG.md \
    main.lua convert.lua run-demo.bat defaults.json.example \
    src tests templates lang hardware importers toolpaths vcarve "$PKG/" )

( cd "$STAGE" && zip -r -q "$OUT/NajjarPro-$VERSION-test.zip" "$(basename "$PKG")" )

echo "packaged: $OUT/NajjarPro-$VERSION-test.zip"
unzip -l "$OUT/NajjarPro-$VERSION-test.zip" | tail -2
