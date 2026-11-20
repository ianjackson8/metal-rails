// metal-rails: Train Sim Classic's stub (RailWorks.exe) and engine
// (plugins/GameManagerVC.dll), lifted by x86recomp, run on its runtime.
//
// Milestone 3: the minimal game target for the startup trace. It runs the
// player's own install (v79.0a) until the first import without a handler,
// which the runtime reports by name. Nothing here answers for the game.
//
// usage: railworks [--game-dir DIR] [-- GAME ARGS...]
//   DIR defaults to $RAILWORKS_GAME_DIR. RAILWORKS_TRACE=1 traces imports.

#include <sys/stat.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "runtime/log.h"
#include "runtime/runtime.h"

int main(int argc, char** argv) {
  std::string game_dir, game_args;
  if (const char* e = std::getenv("RAILWORKS_GAME_DIR")) game_dir = e;
  for (int i = 1; i < argc; i++) {
    if (!std::strcmp(argv[i], "--game-dir") && i + 1 < argc) {
      game_dir = argv[++i];
    } else if (!std::strcmp(argv[i], "--")) {
      for (i++; i < argc; i++) {
        if (!game_args.empty()) game_args += ' ';
        game_args += argv[i];
      }
    } else {
      std::fprintf(stderr, "usage: %s [--game-dir DIR] [-- GAME ARGS...]\n", argv[0]);
      return 2;
    }
  }
  if (game_dir.empty()) {
    std::fprintf(stderr, "railworks: pass --game-dir or set RAILWORKS_GAME_DIR\n");
    return 2;
  }
  while (game_dir.size() > 1 && game_dir.back() == '/') game_dir.pop_back();
  if (const char* t = std::getenv("RAILWORKS_TRACE")) recomp::g_trace = *t && *t != '0';
#if defined(__APPLE__)
  // The D3D9 HLE draws through x86recomp's own Metal renderer (as Liberty
  // Pro Max does), not the generic SDL_GPU backend; RAILWORKS_GFX=gpu in
  // the environment still picks the latter.
  setenv("RAILWORKS_GFX", "metal", 0);
#endif

  const std::string exe = game_dir + "/RailWorks.exe";
  struct stat st;
  if (stat(exe.c_str(), &st) != 0 || stat((game_dir + "/plugins/GameManagerVC.dll").c_str(), &st) != 0) {
    std::fprintf(stderr, "railworks: no RailWorks.exe / plugins/GameManagerVC.dll in %s\n",
                 game_dir.c_str());
    return 2;
  }

  recomp::GameConfig game;
  game.id = "railworks";
  // Where a Steam install puts the game on Windows; the guest sees this path.
  game.guest_dir = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\RailWorks";
  game.exe_name = "RailWorks.exe";
  // The engine DLL the stub LoadLibrary's, the string table DLL the engine
  // LoadLibrary's and minizip (zlibwapi), which both import: lifted together
  // (tools/lift.sh). The two small DLLs share the engine's preferred base,
  // so they are lifted at (and mapped to) bases of their own.
  game.lifted_dlls.push_back({"plugins\\GameManagerVC.dll", 0});
  game.lifted_dlls.push_back({"LocalisedStrings.dll", 0x12000000});
  game.lifted_dlls.push_back({"zlibwapi.dll", 0x12100000});
  // Steam app 24010: the steam_api bridge (recomp_steam) asks the running
  // Steam client about this app (ownership, DLC, the user).
  game.steam_app_id = 24010;
  game.total_phys_mb = 4096;
  game.video_memory_mb = 2048;
  return recomp::RunProcess(game, exe, game_dir, game_args);
}
