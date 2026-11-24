#!/bin/bash
# lift.sh: RailWorks.exe, plugins/GameManagerVC.dll, LocalisedStrings.dll
# and zlibwapi.dll (minizip; v79.0a) translated to C++ in generated/ by one
# multi-module recomp_lift run (--module). The two small DLLs share the
# engine's preferred base 0x10000000, so they are lifted relocated to
# 0x12000000 and 0x12100000, the bases src/main.cpp gives them too; see
# vendor/x86recomp ARCHITECTURE.md "Multiple modules"), with the symbols in
# symbols/{railworks,gamemanager} and this port's changes in manifest/.
# Build the lifter first: cmake --preset release && cmake --build --preset release
#   RAILWORKS_GAME_DIR: the game folder, from the environment or tools/local.env.
# --split-above: d3dx9_43 has a function of ~97k instructions, over 1 MiB
# of arm64 code as one C++ function (branches out of range, hours in
# clang): emitted as parts instead.
# Extra arguments go to recomp_lift. The run's output is kept in logs/lift.log.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
: "${RAILWORKS_GAME_DIR:?set RAILWORKS_GAME_DIR to the RailWorks folder}"
. "$here/tools/hashes.sh"
check_hash RailWorks.exe
check_hash plugins/GameManagerVC.dll
check_hash LocalisedStrings.dll
check_hash zlibwapi.dll
"$here/tools/redist.sh"
d3dx="$("$here/tools/redist.sh" --path)"
lift="${LIFTER:-$here/out/build/release/x86recomp/tools/lifter/recomp_lift}"
[ -x "$lift" ] || { echo "build first (cmake --preset release && cmake --build --preset release): no $lift"; exit 1; }
for m in railworks gamemanager localisedstrings zlibwapi d3dx9_43; do
  [ -f "$here/symbols/$m/functions.tsv" ] || { echo "no symbols/$m/functions.tsv: run tools/ghidra_export.sh"; exit 1; }
done
mkdir -p "$here/logs"
echo "lift.sh: lifting RailWorks.exe, GameManagerVC.dll, LocalisedStrings.dll, zlibwapi.dll, d3dx9_43.dll"
start=$(date +%s)
set +e
(cd "$RAILWORKS_GAME_DIR" && "$lift" \
  --exe RailWorks.exe --symbols "$here/symbols/railworks" \
    --manifest "$here/manifest/railworks.manifest" \
  --module plugins/GameManagerVC.dll --symbols "$here/symbols/gamemanager" \
    --manifest "$here/manifest/gamemanager.manifest" \
  --module LocalisedStrings.dll --symbols "$here/symbols/localisedstrings" \
    --manifest "$here/manifest/localisedstrings.manifest" --base 12000000 \
  --module zlibwapi.dll --symbols "$here/symbols/zlibwapi" \
    --manifest "$here/manifest/zlibwapi.manifest" --base 12100000 \
  --module "$d3dx" --symbols "$here/symbols/d3dx9_43" \
    --manifest "$here/manifest/d3dx9_43.manifest" --base 12200000 \
  --split-above 12000 \
  --out "$here/generated" "$@") 2>&1 | tee "$here/logs/lift.log"
rc=${PIPESTATUS[0]}
set -e
echo "lift.sh: rc=$rc in $(( $(date +%s) - start )) s"
exit "$rc"
