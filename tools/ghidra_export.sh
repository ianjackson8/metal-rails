#!/bin/bash
# ghidra_export.sh [module...]: auto-analyse RailWorks.exe,
# plugins/GameManagerVC.dll, LocalisedStrings.dll, zlibwapi.dll and the
# Microsoft redistributables lifted with them (d3dx9_43, msvcp140; see
# tools/redist.sh) with Ghidra headless (once; the project lives in ghidra/, gitignored) and
# export what the lifter needs into symbols/<module>/:
#   functions.tsv, jumptables.tsv   (Ghidra, x86recomp's tools/ghidra scripts)
#   exports.tsv, imports.tsv, pe_info.txt   (x86recomp's tools/pe_symbols.py)
# Settings come from the environment or tools/local.env:
#   RAILWORKS_GAME_DIR  the game folder (read only)
#   GHIDRA_HOME         Ghidra install (the folder with support/analyzeHeadless)
#   JAVA_HOME           JDK 21+ for Ghidra 12 (optional if java on PATH is one)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$here/tools/local.env" ] && . "$here/tools/local.env"
: "${RAILWORKS_GAME_DIR:?set RAILWORKS_GAME_DIR (tools/local.env)}"
: "${GHIDRA_HOME:?set GHIDRA_HOME to the Ghidra install (tools/local.env)}"
[ -n "${JAVA_HOME:-}" ] && export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"
export GHIDRA_HEADLESS_MAXMEM=${GHIDRA_HEADLESS_MAXMEM:-16G}
H="$GHIDRA_HOME/support/analyzeHeadless"
S="$here/vendor/x86recomp/tools/ghidra"
P="$here/ghidra"; L="$here/logs"
LLVM=${RECOMP_LLVM_ROOT:-/opt/homebrew/opt/llvm@22}
export PATH="$LLVM/bin:$PATH"   # llvm-undname, llvm-objdump
mkdir -p "$P" "$L"
. "$here/tools/hashes.sh"

# module dir, file in the game folder (or an absolute path, already
# verified: the redistributable's d3dx9_43.dll), program name in the project
only=("$@")  # module names to export (default: all)
run() {
  local mod=$1 rel=$2 file prog
  if [ ${#only[@]} -gt 0 ] && [[ ! " ${only[*]} " == *" $mod "* ]]; then return; fi
  prog=$(basename "$rel")
  if [ "${rel:0:1}" = / ]; then file=$rel; else file="$RAILWORKS_GAME_DIR/$rel"; check_hash "$rel"; fi
  mkdir -p "$here/symbols/$mod"
  echo "== $mod: PE facts and exports $(date +%T)"
  python3 -I "$here/vendor/x86recomp/tools/pe_symbols.py" "$file" --out "$here/symbols/$mod"
  if [ ! -d "$P/metal-rails.rep" ] || ! grep -qs "$prog" "$L/ghidra-import-$mod.ok" ; then
    echo "== $mod: import + auto-analysis $(date +%T) (long for the engine DLL)"
    rc=0; "$H" "$P" metal-rails -import "$file" -overwrite \
      -log "$L/ghidra-import-$mod.log" > "$L/ghidra-import-$mod.out" 2>&1 || rc=$?
    [ "$rc" = 0 ] || { echo "import failed rc=$rc, see $L/ghidra-import-$mod.log"; exit 1; }
    echo "$prog" > "$L/ghidra-import-$mod.ok"
  fi
  echo "== $mod: export $(date +%T)"
  rc=0; "$H" "$P" metal-rails -process "$prog" -noanalysis -readOnly -scriptPath "$S" \
    -postScript ExportFunctions.java "$here/symbols/$mod/functions.tsv" \
    -postScript ExportJumpTables.java "$here/symbols/$mod/jumptables.tsv" \
    -log "$L/ghidra-$mod.log" > "$L/ghidra-$mod.out" 2>&1 || rc=$?
  echo "rc=$rc $(grep -h -E "ExportFunctions:|ExportJumpTables:" "$L/ghidra-$mod.out" | tr "\n" " ")"
  # Switch tables Ghidra left empty that have no bounds check for the
  # lifter to size them by (tools/complete_jumptables.py).
  python3 -I "$here/tools/complete_jumptables.py" "$file" "$here/symbols/$mod"
}
run railworks RailWorks.exe
run gamemanager plugins/GameManagerVC.dll
run localisedstrings LocalisedStrings.dll
run zlibwapi zlibwapi.dll
run physxloader PhysXLoader.dll
run physxcooking PhysXCooking.dll
run physxcore PhysXCore.dll
"$here/tools/redist.sh"
run d3dx9_43 "$("$here/tools/redist.sh" --path d3dx9_43)"
run msvcp140 "$("$here/tools/redist.sh" --path msvcp140)"
echo "== done $(date +%T)"
