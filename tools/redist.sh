#!/bin/bash
# redist.sh: Microsoft's d3dx9_43.dll (x86, June 2010 DirectX redistributable),
# which the engine imports and which is lifted with it (tools/lift.sh), taken
# from the player's own Steam install: the Steam client keeps the
# redistributable in steamapps/common/Steamworks Shared/_CommonRedist. The
# DLL is extracted into the game's per-user data folder
# (<data>/redist/d3dx9_43.dll, data = $XDG_DATA_HOME/railworks or, on macOS,
# ~/Library/Application Support/railworks), where src/main.cpp maps it from.
# Nothing from Microsoft goes into this repository.
#   RAILWORKS_GAME_DIR (tools/local.env): the game folder, whose Steam
#   library holds Steamworks Shared; or STEAM_REDIST_DIR, the Jun2010 folder.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
want=0b28546be22c71834501f7d7185ede5d79742457331c7ee09efc14490dd64f5f
if [ -n "${XDG_DATA_HOME:-}" ]; then data="$XDG_DATA_HOME/railworks"
elif [ "$(uname)" = Darwin ]; then data="$HOME/Library/Application Support/railworks"
else data="$HOME/.local/share/railworks"; fi
out="$data/redist/d3dx9_43.dll"
# --path: just say where it goes (for ghidra_export.sh and lift.sh).
[ "${1:-}" = --path ] && { echo "$out"; exit 0; }
if [ -f "$out" ] && [ "$(shasum -a 256 "$out" | cut -d' ' -f1)" = "$want" ]; then
  echo "redist.sh: d3dx9_43.dll present"; exit 0
fi
: "${STEAM_REDIST_DIR:=${RAILWORKS_GAME_DIR:?set RAILWORKS_GAME_DIR}/../Steamworks Shared/_CommonRedist/DirectX/Jun2010}"
cab="$STEAM_REDIST_DIR/Jun2010_d3dx9_43_x86.cab"
[ -f "$cab" ] || { echo "redist.sh: no $cab (install any game that uses the DirectX redistributable, or set STEAM_REDIST_DIR)"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$tmp" && bsdtar -xf "$cab" d3dx9_43.dll)
have=$(shasum -a 256 "$tmp/d3dx9_43.dll" | cut -d' ' -f1)
[ "$have" = "$want" ] || { echo "redist.sh: d3dx9_43.dll is not the June 2010 x86 build (SHA-256 $have)"; exit 1; }
mkdir -p "$data/redist"
cp "$tmp/d3dx9_43.dll" "$out"
echo "redist.sh: d3dx9_43.dll -> $out"
