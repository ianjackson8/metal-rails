#!/bin/bash
# redist.sh: the Microsoft DLLs the engine imports that are lifted with it
# (tools/lift.sh), put into the game's per-user data folder
# (<data>/redist/, data = $XDG_DATA_HOME/railworks or, on macOS,
# ~/Library/Application Support/railworks), where src/main.cpp maps them
# from. Nothing from Microsoft goes into this repository.
#
# - d3dx9_43.dll (x86, June 2010 DirectX), from the player's own Steam
#   install: the Steam client keeps the redistributable in
#   steamapps/common/Steamworks Shared/_CommonRedist.
#     RAILWORKS_GAME_DIR (tools/local.env): the game folder, whose Steam
#     library holds Steamworks Shared; or STEAM_REDIST_DIR, the Jun2010 folder.
# - msvcp140.dll (x86, 14.44.35211.0), from Microsoft's Visual C++
#   redistributable (VC_redist.x86.exe), downloaded once from Microsoft's
#   versioned URL below (the game's Steam redistributables stop at VC++
#   2012). Or VC_REDIST_X86, a copy of that file already on disk.
#
# Every file is checked against its SHA-256. Usage:
#   redist.sh              fetch/extract what is missing
#   redist.sh --path NAME  print where NAME (d3dx9_43, msvcp140) goes
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
if [ -n "${XDG_DATA_HOME:-}" ]; then data="$XDG_DATA_HOME/railworks"
elif [ "$(uname)" = Darwin ]; then data="$HOME/Library/Application Support/railworks"
else data="$HOME/.local/share/railworks"; fi
redist="$data/redist"

if [ "${1:-}" = --path ]; then
  case "${2:-}" in
    d3dx9_43|msvcp140) echo "$redist/$2.dll"; exit 0 ;;
    *) echo "redist.sh --path d3dx9_43|msvcp140"; exit 2 ;;
  esac
fi

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
have() { [ -f "$redist/$1" ] && [ "$(sha "$redist/$1")" = "$2" ]; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$redist"

# d3dx9_43.dll -----------------------------------------------------------------
d3dx_sha=0b28546be22c71834501f7d7185ede5d79742457331c7ee09efc14490dd64f5f
if have d3dx9_43.dll "$d3dx_sha"; then
  echo "redist.sh: d3dx9_43.dll present"
else
  : "${STEAM_REDIST_DIR:=${RAILWORKS_GAME_DIR:?set RAILWORKS_GAME_DIR}/../Steamworks Shared/_CommonRedist/DirectX/Jun2010}"
  cab="$STEAM_REDIST_DIR/Jun2010_d3dx9_43_x86.cab"
  [ -f "$cab" ] || { echo "redist.sh: no $cab (install any game that uses the DirectX redistributable, or set STEAM_REDIST_DIR)"; exit 1; }
  mkdir "$tmp/d3dx"
  (cd "$tmp/d3dx" && bsdtar -xf "$cab" d3dx9_43.dll)
  got=$(sha "$tmp/d3dx/d3dx9_43.dll")
  [ "$got" = "$d3dx_sha" ] || { echo "redist.sh: d3dx9_43.dll is not the June 2010 x86 build (SHA-256 $got)"; exit 1; }
  cp "$tmp/d3dx/d3dx9_43.dll" "$redist/d3dx9_43.dll"
  echo "redist.sh: d3dx9_43.dll -> $redist/d3dx9_43.dll"
fi

# msvcp140.dll -----------------------------------------------------------------
msvcp_sha=97e71a3c697fb1ab3af777db39009e4602525e8c3aff0837ecc7031cba188165
vc_sha=0c09f2611660441084ce0df425c51c11e147e6447963c3690f97e0b25c55ed64
vc_url=https://download.visualstudio.microsoft.com/download/pr/e9604e21-4b79-4096-a4b3-1b63d4b55b4d/0C09F2611660441084CE0DF425C51C11E147E6447963C3690F97E0B25C55ED64/VC_redist.x86.exe
if have msvcp140.dll "$msvcp_sha"; then
  echo "redist.sh: msvcp140.dll present"
else
  exe="${VC_REDIST_X86:-$tmp/VC_redist.x86.exe}"
  if [ ! -f "$exe" ]; then
    echo "redist.sh: downloading VC_redist.x86.exe (14 MB) from Microsoft"
    curl -fsSL -o "$exe" "$vc_url"
  fi
  got=$(sha "$exe")
  [ "$got" = "$vc_sha" ] || { echo "redist.sh: $exe is not VC_redist.x86.exe 14.44.35211 (SHA-256 $got)"; exit 1; }
  # A WiX bundle: its payloads are a cabinet appended to the EXE, holding
  # the MSIs' own cabinets, which hold the DLLs (named <dll>_x86).
  mkdir "$tmp/vc"
  python3 -I - "$exe" "$tmp/vc" <<'EOF'
import os, struct, sys
d = open(sys.argv[1], 'rb').read()
i = n = 0
while (i := d.find(b'MSCF\0\0\0\0', i)) >= 0:
    size = struct.unpack_from('<I', d, i + 8)[0]
    if 0 < size <= len(d) - i:
        open(os.path.join(sys.argv[2], 'outer%d.cab' % n), 'wb').write(d[i:i + size])
        n += 1
    i += 4
EOF
  for c in "$tmp"/vc/outer*.cab; do
    mkdir -p "$c.d" && bsdtar -xf "$c" -C "$c.d"
  done
  for inner in "$tmp"/vc/outer*.cab.d/*; do
    if bsdtar -tf "$inner" 2>/dev/null | grep -qx 'msvcp140.dll_x86'; then
      (cd "$tmp/vc" && bsdtar -xf "$inner" msvcp140.dll_x86)
      break
    fi
  done
  [ -f "$tmp/vc/msvcp140.dll_x86" ] || { echo "redist.sh: no msvcp140.dll in $exe"; exit 1; }
  got=$(sha "$tmp/vc/msvcp140.dll_x86")
  [ "$got" = "$msvcp_sha" ] || { echo "redist.sh: msvcp140.dll is not 14.44.35211.0 x86 (SHA-256 $got)"; exit 1; }
  cp "$tmp/vc/msvcp140.dll_x86" "$redist/msvcp140.dll"
  echo "redist.sh: msvcp140.dll -> $redist/msvcp140.dll"
fi
