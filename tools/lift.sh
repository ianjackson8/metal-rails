#!/bin/bash
# lift.sh: RailWorks.exe and plugins/GameManagerVC.dll (v79.0a) translated
# to C++ in generated/ by one multi-module recomp_lift run (--module; see
# vendor/x86recomp ARCHITECTURE.md "Multiple modules"), with the symbols in
# symbols/{railworks,gamemanager} and this port's changes in manifest/.
# Build the lifter first: cmake --preset release && cmake --build --preset release
#   RAILWORKS_GAME_DIR: the game folder, from the environment or tools/local.env.
# Extra arguments go to recomp_lift. The run's output is kept in logs/lift.log.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
: "${RAILWORKS_GAME_DIR:?set RAILWORKS_GAME_DIR to the RailWorks folder}"
. "$here/tools/hashes.sh"
check_hash RailWorks.exe
check_hash plugins/GameManagerVC.dll
lift="${LIFTER:-$here/out/build/release/x86recomp/tools/lifter/recomp_lift}"
[ -x "$lift" ] || { echo "build first (cmake --preset release && cmake --build --preset release): no $lift"; exit 1; }
for m in railworks gamemanager; do
  [ -f "$here/symbols/$m/functions.tsv" ] || { echo "no symbols/$m/functions.tsv: run tools/ghidra_export.sh"; exit 1; }
done
mkdir -p "$here/logs"
echo "lift.sh: lifting RailWorks.exe + plugins/GameManagerVC.dll"
start=$(date +%s)
set +e
(cd "$RAILWORKS_GAME_DIR" && "$lift" \
  --exe RailWorks.exe --symbols "$here/symbols/railworks" \
    --manifest "$here/manifest/railworks.manifest" \
  --module plugins/GameManagerVC.dll --symbols "$here/symbols/gamemanager" \
    --manifest "$here/manifest/gamemanager.manifest" \
  --out "$here/generated" "$@") 2>&1 | tee "$here/logs/lift.log"
rc=${PIPESTATUS[0]}
set -e
echo "lift.sh: rc=$rc in $(( $(date +%s) - start )) s"
exit "$rc"
