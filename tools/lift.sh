#!/bin/bash
# lift.sh: RailWorks.exe, plugins/GameManagerVC.dll, LocalisedStrings.dll
# and zlibwapi.dll (minizip; v79.0a) translated to C++ in generated/ by one
# multi-module recomp_lift run (--module). The two small DLLs share the
# engine's preferred base 0x10000000, so they are lifted relocated to
# 0x12000000 and 0x12100000, the bases src/main.cpp gives them too; see
# vendor/x86recomp ARCHITECTURE.md "Multiple modules"), with the symbols in
# symbols/{railworks,gamemanager} and this port's changes in manifest/.
# Microsoft's d3dx9_43.dll and msvcp140.dll (tools/redist.sh) are lifted
# with them, at 0x12200000 and 0x12400000; PhysX 2.x (PhysXLoader,
# PhysXCooking, PhysXCore, shipped with the game) at 0x12500000, 0x12600000
# and 0x12700000; SilverLining's DX9 renderer DLL (the sky, shipped in
# data/SilverLining) at 0x12B00000.
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
check_hash PhysXLoader.dll
check_hash PhysXCooking.dll
check_hash PhysXCore.dll
check_hash data/SilverLining/vc143/win32/SilverLiningDirectX9-MT-DLL.dll
"$here/tools/redist.sh"
d3dx="$("$here/tools/redist.sh" --path d3dx9_43)"
msvcp="$("$here/tools/redist.sh" --path msvcp140)"
dcomp="$("$here/tools/redist.sh" --path d3dcompiler_43)"
lift="${LIFTER:-$here/out/build/release/x86recomp/tools/lifter/recomp_lift}"
[ -x "$lift" ] || { echo "build first (cmake --preset release && cmake --build --preset release): no $lift"; exit 1; }
for m in railworks gamemanager localisedstrings zlibwapi physxloader physxcooking physxcore silverlining d3dx9_43 msvcp140 d3dcompiler_43; do
  [ -f "$here/symbols/$m/functions.tsv" ] || { echo "no symbols/$m/functions.tsv: run tools/ghidra_export.sh"; exit 1; }
done
mkdir -p "$here/logs"
echo "lift.sh: lifting RailWorks.exe, GameManagerVC.dll, LocalisedStrings.dll, zlibwapi.dll, PhysX (Loader, Cooking, Core), SilverLining DX9, d3dx9_43.dll, msvcp140.dll, d3dcompiler_43.dll"
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
  --module "$msvcp" --symbols "$here/symbols/msvcp140" \
    --manifest "$here/manifest/msvcp140.manifest" --base 12400000 \
  --module "$dcomp" --symbols "$here/symbols/d3dcompiler_43" \
    --manifest "$here/manifest/d3dcompiler_43.manifest" --base 12C00000 \
  --module PhysXLoader.dll --symbols "$here/symbols/physxloader" \
    --manifest "$here/manifest/physxloader.manifest" --base 12500000 \
  --module PhysXCooking.dll --symbols "$here/symbols/physxcooking" \
    --manifest "$here/manifest/physxcooking.manifest" --base 12600000 \
  --module PhysXCore.dll --symbols "$here/symbols/physxcore" \
    --manifest "$here/manifest/physxcore.manifest" --base 12700000 \
  --module data/SilverLining/vc143/win32/SilverLiningDirectX9-MT-DLL.dll --symbols "$here/symbols/silverlining" \
    --manifest "$here/manifest/silverlining.manifest" --base 12B00000 \
  --split-above 12000 \
  --out "$here/generated" "$@") 2>&1 | tee "$here/logs/lift.log"
rc=${PIPESTATUS[0]}
set -e
echo "lift.sh: rc=$rc in $(( $(date +%s) - start )) s"
exit "$rc"
