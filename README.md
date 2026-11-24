# metal-rails

**Train Sim Classic (RailWorks) running natively on Apple silicon.**

No Wine, no emulator, no virtual machine. The game's 32-bit x86 code is
translated ahead of time into C++ ([static recompilation](#how-it-works)),
compiled for arm64, and linked against a runtime that reimplements the
Windows APIs and middleware the game uses, drawing through Metal.

It follows [Liberty Pro Max](https://github.com/Awis13/liberty-pro-max)
(GTA IV on Apple silicon) and uses the same recompiler,
[x86recomp](https://github.com/ianjackson8/x86recomp) (this project's
fork).

> **Status: early development, not playable.** The game boots through
> Steam, D3D9 on Metal, D3DX, fonts and Steam Cloud. The current goal is
> the main menu.

You need your own copy of Train Sim Classic on Steam. This repository
contains no game files and never will: everything is built from your own
install.

---

## Why

Under Wine/CrossOver the game runs, but in real scenarios its GPU time
collapses from ~20-30 ms to ~150-170 ms (about 6 fps) within seconds of
loading, with a static camera, under both D3DMetal and DXVK (measured on
an M5 Pro). A native renderer is where that has to be beaten.

## Progress

```
Milestone 1   Analyse the game's code (Ghidra)          ██████████  done
Milestone 2   Translate it to C++, go/no-go              ██████████  done (GO)
Milestone 3   Startup: CRT, Steam, window, D3D9 device   ██████████  done
Milestone 4   Main menu on screen                        ██████░░░░  in progress
Milestone 5   Load a route                               ░░░░░░░░░░
Milestone 6   Drive a train (input, PhysX, cab, HUD)     ░░░░░░░░░░
Milestone 7   Correct rendering, DLC                     ░░░░░░░░░░
Milestone 8   Performance (beat the Wine collapse)       ░░░░░░░░░░
Milestone 9   Native launcher, installer                 ░░░░░░░░░░
Milestone 10  Optional: the 64-bit engine                ░░░░░░░░░░
```

What works today, in startup order:

| | |
|---|---|
| ✅ | Launches; **Steam confirms ownership** through Valve's own macOS `libsteam_api` (no DRM bypass) |
| ✅ | Window, **D3D9 device on Metal** (x86recomp's renderer, Liberty's) |
| ✅ | Microsoft's **D3DX 9 (June 2010)**, lifted from your Steam DirectX redistributable |
| ✅ | Shader effects compile; recorded state blocks |
| ✅ | Textures and geometry |
| ✅ | **Text**: Windows GDI fonts rendered with macOS CoreText |
| ✅ | **Steam Cloud**, stats and leaderboards via the Steam client |
| ⏳ | Lua scripting's error handling (`setjmp`/`longjmp`) |
| ⬜ | Audio (OpenAL) |
| ⬜ | Scaleform UI → **main menu** |

The startup trace reaches about a million imported calls before it stops
at the next unimplemented function. Details, addresses and measurements:
[FINDINGS.md](FINDINGS.md).

### Numbers

| | |
|---|---|
| Target build | Steam app 24010, `v79.0a` (build 26760680), hashes pinned |
| Modules lifted | `RailWorks.exe`, `GameManagerVC.dll` (20 MB engine), `LocalisedStrings.dll`, `zlibwapi.dll`, `d3dx9_43.dll` |
| Functions | ~116,000 |
| x86 instructions | ~6.3 million → ~515 generated C++ files |

## How it works

1. **Analyse.** Ghidra exports function addresses and jump tables from
   your copy of the game (`tools/ghidra_export.sh` → `symbols/`).
2. **Lift.** x86recomp's `recomp_lift` translates every function of the
   EXE and its DLLs into C++ (`tools/lift.sh` → `generated/`, never
   committed). The x87 FPU is modelled exactly, SSE bit-exactly.
3. **Run.** The generated code links against x86recomp's runtime, which
   reimplements what the game imports (Win32, the C runtime, D3D9, input,
   Steam, ...). An import with no implementation stops the game with its
   name, so nothing is silently faked.
4. **Draw.** D3D9 calls go to a Metal renderer; shaders are translated
   from the game's own HLSL.

What the game is built from: a 32-bit D3D9 + D3DX engine, Scaleform GFx
menus, Lua scripts, SilverLining sky, OpenAL audio, PhysX 2.x.

## Building

Requirements:

- macOS on Apple silicon, Xcode command line tools, CMake ≥ 3.25, Ninja
- Train Sim Classic installed through Steam (with the Steam client)
- The Steamworks SDK **1.53a** (for the Steam bridge headers)
- Ghidra 12 and a JDK, only if you regenerate `symbols/`

```sh
# 1. Point the tools at your install (this file stays untracked).
cat > tools/local.env <<EOF
RAILWORKS_GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/RailWorks"
STEAMWORKS_SDK=/path/to/steamworks_sdk_153a/sdk
EOF

# 2. x86recomp: the commit pinned in X86RECOMP, in vendor/x86recomp.
#    (Milestone 4 work is on the fork's metal-rails/m4-render branch;
#     configure with -DX86RECOMP_DIR=... to build against it.)

# 3. Build the lifter, then lift your install (checks the game's hashes and
#    extracts d3dx9_43.dll from the Steam DirectX redistributable).
cmake --preset release && cmake --build --preset release
tools/lift.sh

# 4. Build and run the game.
cmake --preset debug && cmake --build --preset debug --target railworks
out/build/debug/railworks --game-dir "$RAILWORKS_GAME_DIR"
```

The first build compiles a lot of generated C++ (D3DX alone has a few
files that take tens of minutes); later builds only recompile what
changed.

## Layout

| Path | |
|---|---|
| `src/` | The port's own code (game configuration, startup) |
| `manifest/` | Per-module lifter manifests (entries, hooks, replacements) |
| `symbols/` | Ghidra exports: function addresses and names, jump tables |
| `tools/` | `lift.sh`, `ghidra_export.sh`, `redist.sh`, hash checks |
| `generated/` | Lifter output (local only) |
| `FINDINGS.md` | What has been learnt about the game, with addresses |
| `CLAUDE.md` | Project rules and plan |

## Rules

- No game files in the repository, ever. Users build from their own install.
- No DRM bypass: ownership and DLC come from the real Steam client.
- No Wine in the product, and no emulation fallback: unlifted code
  reached at runtime is a fatal error.
- Windows/middleware behaviour lives upstream in x86recomp; this repo
  keeps only what is specific to Train Sim Classic.

## Credits

- [x86recomp](https://github.com/JTM-rootstorm/x86recomp) and
  [Liberty Pro Max](https://github.com/Awis13/liberty-pro-max), whose
  recompiler, runtime and Metal renderer this builds on.
- Train Sim Classic is © Dovetail Games. This is an unofficial,
  non-commercial interoperability project; it ships none of their code or
  content.
