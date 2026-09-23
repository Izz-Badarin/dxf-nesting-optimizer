#!/bin/sh
# Build a standalone Lua 5.4 interpreter for Najjar Pro core development.
# Usage: sh tools/build-lua.sh   (requires gcc + git; no root needed)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/_lua-src"
mkdir -p "$SRC"
if [ ! -f "$SRC/lua.c" ]; then
  git clone --depth 1 --branch v5.4.6 https://github.com/lua/lua "$SRC"
fi
cd "$SRC"
CORE=$(ls *.c | grep -v -E '^(lua|luac|onelua|ltests)\.c$' | tr '\n' ' ')
gcc -O2 -w -DLUA_USE_POSIX -o lua lua.c $CORE -lm
mkdir -p "$ROOT/tools/lua/bin"
cp lua "$ROOT/tools/lua/bin/lua"
"$ROOT/tools/lua/bin/lua" -v
