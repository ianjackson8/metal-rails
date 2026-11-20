# Sourced by tools/*.sh: the one build this port targets (v79.0a, Steam
# buildid 26760680). check_hash <path relative to RAILWORKS_GAME_DIR>.
check_hash() {
  local want
  case "$1" in
    RailWorks.exe)             want=2cc701c6b885a1f094fd6bfc8ba5903a2dfb2b08c9775a7a51b9d6f2cbc6486c ;;
    RailWorks64.exe)           want=ce909f0f004c423466e9a1cd4ab3da7abffd444d1e46777cbdb5a54f7c4ac1a0 ;;
    plugins/GameManagerVC.dll) want=ab920b554f13869559a9888f44102b96ddac8061e44b90f2263f97ea4bc75169 ;;
    plugins/GameManagerVC64.dll) want=6dcc422143de7ebb3a5a2d2913bb2b8742858a05978ce5cfc3bfb827d1ae56ba ;;
    LocalisedStrings.dll)      want=750cab94d96ec322087dd1e2e4fab7ec7cb843951d0744c5a3f6de00c2b7b1d2 ;;
    zlibwapi.dll)              want=9f8729ac49e0ccea86fe3b1a9b2c3fae9986ecd09db92853e7a588dbda85bf90 ;;
    *) echo "check_hash: no pinned hash for $1"; exit 1 ;;
  esac
  local have
  have=$(shasum -a 256 "$RAILWORKS_GAME_DIR/$1" | cut -d' ' -f1)
  [ "$have" = "$want" ] || { echo "$1 is not v79.0a (SHA-256 $have, want $want)"; exit 1; }
}
