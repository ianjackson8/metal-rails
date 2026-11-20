# metal-rails

Train Simulator Classic (RailWorks) running natively on Apple silicon by
static recompilation, on the model of
[Liberty Pro Max](../liberty-pro-max) (GTA IV): the game's x86 code is
lifted to C++ with x86recomp and linked against a runtime that
reimplements the Windows APIs and middleware the game uses, with a Metal
renderer. No Wine, no emulation, no VM in the product.

Status: **milestones 1-2 done, GO (2026-11-20).** The stub + engine lift
in one multi-module run; details, HLE gap table and the milestone 3 plan
in FINDINGS.md. Feasibility was screened at 55/100 (see "Feasibility"
below).

## Hard rules

- **No game files in this repo, ever.** No EXEs, DLLs, shaders, assets,
  generated/ output, Ghidra databases or extracted data. Users build from
  their own install. Keep `generated/` and any local paths in .gitignore
  and `tools/local.env` (untracked).
- **No DRM bypass.** Steam ownership and DLC entitlement must be answered
  by the real Steam client (bridge `steam_api.dll` to Valve's macOS
  `libsteam_api.dylib`), never stubbed to "owned".
- **No Wine in the product.** Wine running the original game is allowed
  only as a dev-time behaviour reference (see "Wine reference setup").
- Follow x86recomp's own rules (`vendor/x86recomp/CLAUDE.md` once
  vendored): no emulation fallback, exact x87/SSE semantics, no x86
  intrinsics or inline asm, macOS arm64 + Metal is a hard requirement,
  new graphics front ends go through `gfx::Device`.
- Behaviour of a Windows or middleware API belongs upstream in
  x86recomp's docs; this repo's CLAUDE.md / FINDINGS.md hold only what is
  specific to Train Sim Classic.
- Commit or push only when asked.

## Target build (pin it)

The game is still patched by Dovetail, so the port targets one build:

- Steam app 24010, version `v79.0a`, buildid `26760680`.
- SHA-256:
  - `RailWorks.exe` (32-bit stub) `2cc701c6b885a1f094fd6bfc8ba5903a2dfb2b08c9775a7a51b9d6f2cbc6486c`
  - `RailWorks64.exe` `ce909f0f004c423466e9a1cd4ab3da7abffd444d1e46777cbdb5a54f7c4ac1a0`
  - `plugins/GameManagerVC.dll` (32-bit engine) `ab920b554f13869559a9888f44102b96ddac8061e44b90f2263f97ea4bc75169`
  - `plugins/GameManagerVC64.dll` `6dcc422143de7ebb3a5a2d2913bb2b8742858a05978ce5cfc3bfb827d1ae56ba`
- Pin the depot manifest for DepotDownloader once chosen (as Liberty
  does for GTA IV 1.0.8.0) and verify hashes in `tools/lift.sh`.
- Local install used for screening:
  `~/Library/Application Support/Steam/steamapps/common/RailWorks`
  (20 GB incl. DLC).

## What Train Sim Classic is made of (screening findings)

- **The EXEs are stubs** (~380 KB). They load `plugins\GameManager*.dll`,
  `GameEditor.dll`, `GameTiming.dll`. The engine is
  `plugins/GameManagerVC.dll`: 20 MB, PE32 i386, roughly GTA IV-sized.
  64-bit (`GameManagerVC64.dll`) and DX12 (`GameManagerDX12_VC64.dll`)
  variants also ship.
- **Graphics: Direct3D 9 + D3DX9 (`d3dx9_43`).** Shaders ship
  **precompiled**: 131 `dev/Shaders/*.fx` sources (130 with techniques)
  sit next to 132 `*.fx.o` fx_2_0 effect binaries built offline with
  `fxc /T fx_2_0`, and the engine loads the `.fx.o` files through
  `D3DXCreateEffectFromFileA`, i.e. the **ID3DXEffect** framework over
  SM2/SM3 bytecode. It also imports `D3DXCompileShaderFromFileA` and
  `D3DXAssembleShaderFromFileA` (a few `.vsh`). x86recomp has an HLSL
  translator and an SM1-3 bytecode front end, but no effect framework,
  and its D3DX9 HLE is registered as `d3dx9_35` (3 of the engine's 38
  D3DX imports). Liberty's D3D9 to Metal renderer is the base.
- **UI: Scaleform GFx**, statically linked (menus are `.swf` in
  `data/scaleform`). Lifted with the rest; draws through D3D9.
- **Sky: SilverLining** (Sundog). The engine names DX9/DX11/GL/Vulkan
  SilverLining DLLs, none are shipped; shaders in `data/SilverLining`.
  Find out whether it is statically linked or optional.
- **Audio: OpenAL** (`OpenAL32.dll`/`OpenAL64.dll` shipped). Needs a new
  HLE module, simplest as a pass-through to native OpenAL Soft.
- **Physics: PhysX 2.x** (`PhysXLoader/Core/Cooking/Device.dll`, optional
  CUDA `cudart32_30_9.dll`). Lift these DLLs too, GPU physics off.
- **Input:** DirectInput 8, XInput 1.4/1.3, plus `RailDriver.dll`
  (hardware controller) and TrackIR (`NPClient`). Stub the latter two first.
- **C runtime: modern MSVC (UCRT `api-ms-win-crt-*`, `MSVCP140`,
  `VCRUNTIME140`) on a 32-bit guest.** x86recomp's UCRT/MSVCP140 HLE
  exists only for x64 guests and is in progress. This is the biggest
  runtime gap.
- **Other imports (engine):** `LocalisedStrings.dll` (a game DLL),
  `zlibwapi` (by ordinal), `gdiplus`, `comctl32`, `comdlg32`, `urlmon`,
  `ws2_32`, `winmm`, `steam_api.dll`. The shipped `stlport_vc10`,
  `libmmd` and `svml_dispmd` are **not** used by the engine
  (`stlport_vc10` only by the tools DLL `ConvertToTGLib.dll`).
- **Scripting:** Lua (engine embeds it; scripts are compiled bytecode).
  Lifted as part of the engine.
- **Launcher / tools are .NET** (`TSCLauncher.exe`, editors). Out of
  scope: replace with a native launcher like Liberty's.
- **Memory:** the 32-bit build runs out of address space on heavy routes
  (why DTG added 64-bit). Start 32-bit (x86recomp's most mature path),
  plan a later move to the x64 engine.

## Liberty Pro Max: what to copy

Repo: `../liberty-pro-max` (github.com/Awis13/liberty-pro-max).

- **x86recomp** is pinned in `X86RECOMP` (`branch commit repo-url`):
  this project's fork github.com/ianjackson8/x86recomp, branch
  `metal-rails/m3-crt32` (commit `b7b60398...`), vendored at
  `vendor/x86recomp`. The fork is Liberty's base (Awis13/x86recomp,
  `liberty` branch, commit `2461249e`) plus metal-rails' signed changes.
  That branch carries the Metal renderer, audio mixer and Windows layer.
  Upstream: github.com/JTM-rootstorm/x86recomp.
- **Pipeline:** `symbols/` (function addresses + names from Ghidra,
  `tools/ghidra_export.sh`) + `manifest/<game>.manifest` (port's changes)
  -> `recomp_lift` -> `generated/` (never committed) -> CMake
  `recomp_add_lifted()` + `add_subdirectory(x86recomp)`.
- **Manifest grammar** (line based, guest VAs in hex):
  `entry <va> [name] | name <va> <name> | probe <va> [name] | resume <va>
  | setjmp <va> [name] | replace <va> [name] | hook <va> <end>`.
  `replace` swaps a guest function for C++ (Liberty uses it for the PAUL
  copy layer and GFWL offline answers; here it would be for things like
  the Steam bridge, not for bypassing ownership).
- **Speed path:** `manifest/native.list` names hot functions;
  `tools/x86n.py` re-translates them to plain C++ (registers as locals,
  flags only where read). Plus `RECOMP_LTO` (ThinLTO),
  `RECOMP_SSE_HOST` (host SSE arithmetic when the game never reads NaN
  payloads/MXCSR flags), PGO (`tools/pgo.sh`). Liberty went 20-52 fps
  (generic SDL GPU) -> 34-88 (own Metal renderer) -> ~90 avg with all of
  the above.
- **Multi-module lifting is supported** (x86recomp ARCHITECTURE.md,
  "Multiple modules"): one lifter run takes the EXE plus each DLL
  (`--module`), `GameConfig::lifted_dlls` maps them at startup,
  LoadLibrary/FreeLibrary/DllMain work. Static TLS in a lifted 32-bit
  DLL is refused (check the engine DLL for a TLS directory early).
- **x86recomp HLE modules available today:** Win32 (kernel32, user32,
  gdi32, advapi32, shfolder, ...), D3D9 + D3DX9 (in progress),
  DirectDraw7/D3D7, OpenGL 1.x, DirectSound 8, DirectInput 8, XInput,
  dbghelp, Miles, Bink, MSVCP140/UCRT (x64 only). No OpenAL, no PhysX,
  no Scaleform-specific code needed, no Steam.
- Layout to mirror: `src/` (port code, launcher `.mm`), `manifest/`,
  `symbols/`, `tools/` (lift.sh, ghidra export, pgo), `tests/`,
  `builder/` (one-click Builder app), `install.sh`.

## Feasibility (screened 2026-11-20): 55/100

For: 32-bit D3D9 engine (exactly what x86recomp + Liberty's Metal
renderer target), shader sources ship next to the compiled effects,
multi-module lifting exists,
DInput/XInput exist, a train sim is far less timing-sensitive than GTA.

Against: no community reverse engineering (GTA IV had FusionFix,
ZolikaPatch and years of symbols; here it is Ghidra auto-analysis of an
unnamed 20 MB DLL), the 32-bit UCRT/MSVCP140 gap, PhysX 2.x and OpenAL
modules to add, D3DX effect framework surface, a still-patched target,
32-bit address space limits.

### First go/no-go milestones
1. **Done (2026-11-20).** Ghidra-analyse `GameManagerVC.dll` + the EXE
   stub; export symbols.
2. **Done, GO (2026-11-20).** Lift EXE + `GameManagerVC.dll` with
   `--module`; count unlifted/unresolved targets; check for static TLS
   (present, 8 bytes, no callbacks: needs an upstream runtime change).
   PhysX DLLs to be added as further modules.
3. Startup trace: imports actually called at startup vs. HLE coverage
   (the static inventory is done, FINDINGS.md); size the 32-bit
   UCRT/VCRUNTIME/MSVCP140 work. Starts with the three small upstream
   x86recomp changes (32-bit DLL static TLS, SSE2 saturating arithmetic,
   `xinput1_4` alias).
4. D3DX: usage measured (`ID3DXEffect` over fx_2_0 binaries); implement
   the effect framework.
5. Reach the main menu (Scaleform) before any 3D.

## Why native and not Wine (measured)

Tried before starting this repo, on an M5 Pro (48 GB, macOS 27.0):
Sikarugir wrapper (Wine 11.0) with Windows Steam inside, game files
APFS-cloned in. It runs (menus 60 fps, Steam/DLC fine) but **in a
scenario the GPU time collapses from ~20-30 ms to ~150-170 ms (6 fps)
within ~10 s of loading, with a static camera**, then stays there.
Identical under D3DMetal (DX12 exe) and DXVK (DX9 64-bit exe). Not
fixed by: resolution (3024x1964 -> 1512x982), MSAA off (FXAA only),
Procedural Flora off, post effects off. Memory, power and thermals were
fine. Root cause unknown: when the Metal renderer exists, capture a
frame of that scenario (Victorville yard, Cajon Pass route) and compare;
the native renderer is where this must be beaten.

Side finding: the sky/smoke colour banding went away with Adaptive
Bloom off.

### Wine reference setup (dev-time only)
- Wrapper: `~/Applications/Sikarugir/TrainSim.app` (Sikarugir 1.0.2,
  template 1.0.27, engine WS12WineSikarugir11.0_1).
- Prefix: `.../TrainSim.app/Contents/SharedSupport/prefix`; Wine binaries
  need `DYLD_FALLBACK_LIBRARY_PATH=.../Contents/Frameworks`.
- Settings live in `.../Contents/Info.plist` (D3DMETAL, DXVK, METAL_HUD,
  WINEDEBUG). Backup: `~/Applications/Sikarugir/TrainSim.Info.plist.bak`.
- Stop everything: `wineserver -k` with that prefix and library path.

## Working conventions

- Prefer measured claims; record numbers (fps, GPU ms, scene) with the
  build and settings that produced them.
- Before editing generated output, change the manifest or lifter instead;
  `generated/` is disposable.
- When touching the lifter (upstream), diff a game's `generated/` before
  and after.
- Keep FINDINGS.md for game-specific discoveries (addresses, structures,
  quirks), with the build hash they apply to.
- Never commit secrets, Steam credentials, or local paths with usernames
  outside `tools/local.env`.
