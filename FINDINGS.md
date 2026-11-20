# FINDINGS

Game-specific discoveries for Train Sim Classic. Every entry names the
build it applies to. Behaviour of Windows/middleware APIs goes upstream in
x86recomp's docs, not here.

## Target build (verified 2026-11-20)

Steam app 24010, v79.0a, buildid 26760680. SHA-256 of the local install
(`~/Library/Application Support/Steam/steamapps/common/RailWorks`),
all four match CLAUDE.md:

| File | SHA-256 |
|---|---|
| `RailWorks.exe` | `2cc701c6b885a1f094fd6bfc8ba5903a2dfb2b08c9775a7a51b9d6f2cbc6486c` |
| `RailWorks64.exe` | `ce909f0f004c423466e9a1cd4ab3da7abffd444d1e46777cbdb5a54f7c4ac1a0` |
| `plugins/GameManagerVC.dll` | `ab920b554f13869559a9888f44102b96ddac8061e44b90f2263f97ea4bc75169` |
| `plugins/GameManagerVC64.dll` | `6dcc422143de7ebb3a5a2d2913bb2b8742858a05978ce5cfc3bfb827d1ae56ba` |

`tools/hashes.sh` checks these before any export or lift.

## Toolchain (2026-11-20)

- **Ghidra 12.2** (Homebrew, `/opt/homebrew/opt/ghidra/libexec`) with
  **OpenJDK 25** (Homebrew `openjdk@25`). Liberty used Ghidra 12.1.4 with
  JDK 21; x86recomp's `ExportFunctions.java` / `ExportJumpTables.java` run
  unchanged on 12.2.

- x86recomp vendored at `vendor/x86recomp`, commit `2461249e` (Liberty's
  pin, `liberty` branch), clean checkout. Liberty's own vendored copy
  carries an uncommitted 9-line change to `src/runtime/process.cpp` that
  is *not* included here.
- `recomp_lift` builds with `cmake --preset release && cmake --build
  --preset release` (target `recomp_lift` only; configure ~58 s incl.
  fetching Zydis v4.1.1, build ~2 s wall). Configuring the x86recomp tree
  still requires SDL3, ffmpeg, glslang and SPIRV-Cross, all present via
  Homebrew on this machine.
- LLVM 22 (Homebrew `llvm@22`) provides `llvm-undname` / `llvm-objdump`;
  they are not on PATH by default, and the scripts add them.

## PE facts: v79.0a

`tools/ghidra_export.sh` writes these to `symbols/*/pe_info.txt` and
`imports.tsv` (x86recomp `tools/pe_symbols.py`).

### `RailWorks.exe` (stub)
- Image base `0x00400000`, size `0x61000`, **no relocations** (fixed base),
  entry `0x0040181C`, `.text` 0x142B bytes. **No TLS.** 0 exports.
- Built with MSVC 2015+ (UCRT/VCRUNTIME140 imports). Imports only
  KERNEL32 (25), USER32 (3), VCRUNTIME140 (10), UCRT API sets (28).
- `LoadLibrary`s by name (strings): `plugins\GameManagerVC.dll`,
  `plugins\GameManager.dll`, `plugins\GameEditor.dll`,
  `plugins\GameTiming.dll`. Only `GameManagerVC.dll` ships; the other three
  are optional variants (editor/timing/non-VC builds). Also `-RStiming`
  on the command line. Uses Toolhelp (`Process32First/Next`), `EnumWindows`
  and `SetForegroundWindow`, likely a single-instance check.

### `plugins/GameManagerVC.dll` (engine)
- Image base `0x10000000`, size `0x1F07000` (ends `0x11F07000`, no overlap
  with the stub, so no `--base` needed), has relocations, entry
  `0x10E29EDC`. Sections: `.text` 0xFA22AF (15.6 MiB), `.rdata` 0x1D0994,
  `.data` vsize 0xC9114C (12.6 MiB, 0.7 MiB initialised), `.rsrc`,
  `.reloc`. 36 exports (all functions). Rich header: VS 2022 toolset
  (build 33030/33145).
- **Static TLS: yes.** `IMAGE_TLS_DIRECTORY` with template
  `0x1115758C..0x11157594` (8 bytes: `00000000 00000080`), zero fill 0,
  index at `0x11BB6A44`, callbacks array `0x10FAD174` **empty** (first
  entry 0). The template matches MSVC's thread-safe static init
  (`_Init_thread_epoch` starts at INT_MIN); i.e. compiler-generated
  (`/Zc:threadSafeInit`), not game `__declspec(thread)` data.
  - x86recomp at `2461249e`: the **lifter accepts it** (pe_image.cpp only
    records the directory). The **runtime refuses it at map time**
    (`process.cpp` `MapModuleWith`: "lifted DLL %s has static TLS ...: not
    supported" when `!p.x64`). The x64 path already gives each lifted DLL
    its own slot after the EXE's, writes `tls_index`, and copies the
    template per thread in `InitTeb` with the 32-bit TEB layout
    (`fs:[0x2C]`) already in place. Extending that to 32-bit guests
    (Vista+ semantics, which a VS 2022 DLL assumes) looks small; the "XP
    did not do this" rationale does not apply to a 2025 build. Upstream
    change, x86recomp.

### Engine's DLL dependencies (shipped 32-bit DLLs)
| DLL | Imports by engine | Notes |
|---|---|---|
| `LocalisedStrings.dll` | 5 (`GetLanguage`, `GetStringByStr`, ...) | MSVC 2015+, imports zlibwapi/MSVCP140/VCRUNTIME140. Lift as a third module, or HLE 5 functions over its data |
| `zlibwapi.dll` | 17, **by ordinal** | plain zlib (WINAPI build): HLE onto host zlib |
| `PhysXLoader.dll` / `PhysXCooking.dll` | 2 / 3 | `NxCreatePhysicsSDK`, `NxGetUtilLib`; `NxInitCooking`, `NxCookTriangleMesh`, `NxCloseCooking`. Loader pulls `PhysXCore.dll` (imports `cudart32_30_9`, WSOCK32) and `PhysXDevice.dll` at run time. Old MSVC, no TLS |
| `OpenAL32.dll` | 35 | has TLS; replace by HLE, not lifted |
| `steam_api.dll` | 13 flat exports | has TLS; bridge, not lifted |

Not used by the engine, despite CLAUDE.md's screening list:
`stlport_vc10.5.2.dll` (only `ConvertToTGLib.dll`, a tools DLL the engine
does not import, uses it), `libmmd.dll`, `svml_dispmd.dll` (no shipped
32-bit DLL imports them), `d3dx9_26.dll`. `d3dx9_43.dll` is not shipped
(a system DLL), so it can only be HLE. Seven .NET assemblies
(TypeEdit.*, RWAceToolLib, SharpZipLib) are tools, out of scope.

### Shaders (correcting CLAUDE.md)
`dev/Shaders` holds 131 `.fx` (130 with `technique` blocks), 9 `.fxh`
and **132 `.fx.o`**: fx_2_0 effect binaries (magic `01 09 FF FE`), built
offline by the shipped `Compile*.bat` (`fxc /Gec /T fx_2_0 /Od /Zi`).
The engine loads the **`.fx.o`** files through
`D3DXCreateEffectFromFileA(..., "dev/shaders/X.fx.o", 0, 0,
D3DXFX_LARGEADDRESSAWARE, ...)` (assert strings), i.e. it uses
**ID3DXEffect** with precompiled SM2/SM3 bytecode (`vs/ps_2_0`,
`vs/ps_3_0` targets). Every `.fx.o` has its `.fx` source next to it.
It also imports `D3DXCompileShaderFromFileA` and
`D3DXAssembleShaderFromFileA` (`Dev/Shaders/%ls.vsh`; 3 `.vsh` ship).
`data/SilverLining` has 19 more `.fx` (sky); 38 `.hlsl` elsewhere.
("302 files" in CLAUDE.md counted more than `.fx`.)

### Steam interfaces requested
`SteamClient020`, `SteamUser021`, `SteamFriends017`, `SteamUtils010`,
`STEAMAPPS_INTERFACE_VERSION008`, `STEAMUSERSTATS_INTERFACE_VERSION012`;
uses rich presence (`route`, `loco`, `driver_status`). Flat entry points
`SteamAPI_Init`, `SteamAPI_RestartAppIfNecessary`, `SteamAPI_RunCallbacks`,
`SteamAPI_(Un)RegisterCallback/CallResult`, `SteamInternal_ContextInit`,
`SteamInternal_CreateInterface`, `SteamInternal_FindOrCreateUserInterface`,
`SteamAPI_GetHSteamUser`, `SteamAPI_WriteMiniDump`,
`SteamAPI_SetMiniDumpComment`.

## Milestone 1: Ghidra analysis (done 2026-11-20)

`tools/ghidra_export.sh`, Ghidra 12.2 headless, default auto-analysis,
M5 Pro 48 GB, `GHIDRA_HEADLESS_MAXMEM=16G`. Whole script 5 min 13 s.

| Module | Analysis | Functions | Multi-chunk | Thunks | Jump tables resolved / unresolved |
|---|---|---|---|---|---|
| `RailWorks.exe` | seconds | 72 | 3 | 27 | 0 / 26 |
| `GameManagerVC.dll` | 291 s | 78,802 | 1,928 | 627 | 831 / 1,690 |

Ghidra applied `windows_vs12_32` types and named the statically linked
ATL/CRT pieces (e.g. `ATL::CAtlComModule::Term`); game code is
`FUN_xxxxxxxx` (no RTTI-derived class names were exported; Ghidra's RTTI
analyser output could be mined later for vtable/class names).

**The "unresolved" jump tables are mostly not switch tables.**
Classified by instruction form (GameManagerVC.dll):

| Form | Count | What it is |
|---|---|---|
| `jmp [abs32]` into the IAT | 508 | import thunks |
| `jmp reg` | 407 | computed tail calls |
| `jmp [reg+disp]` | 401 | vtable / member-pointer tail calls |
| `jmp [idx*4+disp32]` | 360 | **switch tables** |
| `jmp [abs32]` not IAT | 11 | calls through global function pointers |
| other | 3 | |

The stub's 26 are all import thunks. The lifter recovers switch tables
itself (357 recovered from the image, 13 Ghidra tables completed).

Liberty's `tools/complete_jumptables.py` (GPLv3, **run from Liberty's
checkout against a scratch copy, not vendored**) fills 399 tables (197
sized by their bound check, 202 by its pointer-run heuristic). Relifting
with that: 1,230 tables from symbols, 0 left for the lifter (vs 831+357 =
1,188), functions 109,632 (-2), instructions +1,175, unimplemented sites
unchanged. Gain: ~42 tables, not needed to proceed; if adopted later,
check the 202 heuristic-sized ones first, and decide the licence question
(vendor it as GPL, or write an MIT equivalent).

## Milestone 2: multi-module lift (done 2026-11-20)

`tools/lift.sh` = `recomp_lift --exe RailWorks.exe --module
plugins/GameManagerVC.dll` with empty manifests, x86recomp `2461249e`,
symbols as above (no jump-table completer).

- **rc 0, 58.6 s wall** (single-threaded), 1.1 GB peak RSS.
- **109,634 functions**: 78,874 from Ghidra/exports, 30,760 discovered
  (9,513 via code pointers, 21,138 via data pointers; 30,651 weak).
  Per module: RailWorks 109 functions / 1,623 instructions; GameManagerVC
  109,525 / 4,798,209.
- **4,799,832 instructions** in 397 files (`generated/` 583 MB).
- Jump tables: 831 from Ghidra (13 completed from the image) + 357
  recovered.
- No lifter errors. Warnings: 5 undecodable byte runs, 1 branch outside
  `.text` (`10EF1440 -> 1000036B`), all in junk decodes (below).
- Flags: 46 entries read flags at entry; 45 are "address taken" weak
  entries (data constants such as `0x10D810A8`, `0x10E010B0` taken for
  code pointers), 1 is `105215C0`, a wrapper around `RaiseException`
  (execution can resume in the caller through a handler: expected).
- **Compiles:** `gen_000.cpp` (stub) and engine files 000/200/390 compile
  with the flags `recomp_add_lifted` uses (`-O2 -g0 ...`), 0 errors,
  1-2 s per 1.4 MB file. Not linked (no game target yet).
- No static TLS problem at lift time (see PE facts: the refusal is in the
  runtime loader).

**385 unimplemented sites** (`generated/lift_report.txt`; fatal only if
reached):

| Group | Sites | Assessment |
|---|---|---|
| SSSE3/SSE4.1/SSE4.2/BMI (`pshufb` 40, `pextrd` 36, `pblendvb` 36, `pcmpeqq` 14, `pcmpgtq` 4, `popcnt` 16, `tzcnt` 16) | 162 | almost all in `0x10E23xxx-0x10E29xxx`, the statically linked VS 2022 STL vectorised algorithms, dispatched on ISA-level globals (`cmp [0x11BB6D78], 6` x10, `cmp [0x11BB6A18], 2`), which the CRT sets from CPUID. Expected unreachable under x86recomp's fixed SSE2-class CPUID; **verify at run time** |
| AVX/AVX2/AVX-512DQ (`vpmovmskb` 28, `vmovd` 18, `vpshufb` 12, `vpermq` 9, `vpcmpeq*` 24, ... `vcvt*qq*` 4) | 136 | same region, same gating |
| `xgetbv` | 2 | CRT CPU-feature probe (stub `0x4020F9` and engine); behind the OSXSAVE CPUID bit, which x86recomp does not claim |
| **SSE2 `paddsw` x4, `psubsb` x2** | 6 | **real, reachable code** (`FUN_108d4da0`, XMM operands). Lifter gap: SSE2 saturating integer arithmetic. Small upstream addition |
| junk decodes (`out` 32, `in` 7, `outs*` 9, `ins*` 2, `aas`/`aam`/`daa`/`das` 13, `cli`/`sti` 4, `enter` 2, `les`, `sldt`, `ffreep` 2, undecodable 5, `jmp` far 1) | 79 | data in `.text` (e.g. `0x10C0DFxx` pointer tables) decoded as code from false weak entries. Harmless unless reached |

## HLE coverage (step 6)

Against x86recomp `2461249e`. Classes: **ok** = registered and written
for 32-bit guests (`HLE`/`HLE_NAMED`, or `HLE64` outside the CRT files);
**crt64** = registered via `HLE64` in `ucrt*`/`msvcp140`/`vcruntime*`,
which binds for a 32-bit guest but is written for x64 (8-byte pointers
via `Wr64/Rd64`, x64 table-based EH) and needs a 32-bit audit or rewrite;
**missing** = no handler (fatal if called).

GameManagerVC.dll (RailWorks.exe needs 28 crt64 + 6 missing on top: 2
USER32, 2 VCRUNTIME, 2 UCRT):

| DLL | Total | ok | crt64 | missing | Gap |
|---|---|---|---|---|---|
| UCRT API sets (`api-ms-win-crt-*`) | 212 | 0 | 76 | 136 | **Large.** stdio `__stdio_common_*` (printf/scanf families, wide too), x87-stack intrinsics `_CIacos.._CItan` (13: args/result on the guest x87 stack, must use the exact x87 model), `_libm_sse2_*_precise` (11: XMM0 in/out), locale, `_stat64i32`, signal/raise, `_controlfp_s`/`_clearfp`. Plus all 76 crt64 entries audited for 4-byte pointers |
| `MSVCP140.dll` | 144 | 0 | 2 | 142 | **Large.** x86 mangling (`QAE`, `PBD`) never matches the x64 names registered; content is iostreams + locale (`basic_streambuf/istream/ostream/iostream`, `codecvt`, `ctype`, `_Locinfo`, `_Lockit`), vtable data exports (`??_7basic_ostream...`), `cout`/`cerr` objects. Guest subclasses these, so MSVC's x86 layouts must be exact |
| `VCRUNTIME140.dll` | 32 | 0 | 17 | 15 | **Medium-large, critical path.** 32-bit EH: `__CxxFrameHandler3`, `_except_handler3`, `_except_handler4_common`, `_setjmp3`/`longjmp`, RTTI (`__RTDynamicCast`, `__RTtypeid`, `__RTCastToVoid`). The existing `_CxxThrowException` is x64-only. Builds on the existing 32-bit SEH chain (`kernel32_seh.cpp`, `RtlUnwind`, manifest `resume`) |
| `d3dx9_43.dll` | 38 | 0 | 0 | 38 | **Large.** HLE exists as `d3dx9_35` (577 lines, 3 of 38 would match with an alias). Needed: **ID3DXEffect over fx_2_0 binaries** (`D3DXCreateEffectFromFileA`), `D3DXCompileShaderFromFileA`, `D3DXAssembleShaderFromFileA`, texture file loading (A/W/InMemoryEx, cube, volume, `D3DXFillTextureTX`, `D3DXCreateTextureShader`), `ID3DXSprite`/`Font`/`Line`, `D3DXCreateBox/Sphere`, save-to-file, ~12 math helpers. The SM1-3 bytecode front end (`runtime/hlsl/bytecode.cpp`) can take the effect's embedded shaders |
| `OpenAL32.dll` | 35 | 0 | 0 | 35 | **Medium.** New module; straightforward pass-through to host OpenAL (macOS OpenAL framework, or OpenAL Soft) with guest-pointer conversion; `alGetProcAddress` needs a policy for extensions |
| `KERNEL32.dll` | 140 | 118 | 0 | 22 | **Medium**, because of **fibers** (`ConvertThreadToFiber`, `CreateFiber`, `SwitchToFiber`, `DeleteFiber`): lifted code keeps host stack frames, so each fiber needs its own host stack/context switch; design decision upstream. Rest small: `SleepConditionVariableSRW`, `CreateFileMappingW`, `CreateProcessW`, `WriteProcessMemory`, `K32GetProcessMemoryInfo`, private-profile W, `VerifyVersionInfoW` |
| `USER32.dll` | 68 | 51 | 0 | 17 | Small-medium: dialogs (`CreateDialog*`, `DialogBoxIndirectParamA`), `MonitorFromWindow`/`GetMonitorInfoA`, W variants |
| `zlibwapi.dll` | 17 | 0 | 0 | 17 | Small: by-ordinal, map onto host zlib |
| `WS2_32.dll` | 30 | 14 | 0 | 16 | Small: by-ordinal BSD calls + `getaddrinfo` family (may be only the multiplayer/telemetry path) |
| `steam_api.dll` | 13 | 0 | 0 | 13 | **Medium.** Bridge to Valve's macOS `libsteam_api.dylib` (never stubbed to "owned"): 13 flat calls + guest-callable vtables for 6 interfaces (32-bit thiscall to native 64-bit), callbacks/call results back into guest code |
| `ADVAPI32.dll` | 18 | 5 | 0 | 13 | Small-medium: CryptoAPI hash/encrypt (CommonCrypto), 2 registry W calls |
| `gdiplus.dll` | 11 | 0 | 0 | 11 | Small: image decode from stream + LockBits (ImageIO) |
| `GDI32.dll` | 12 | 4 | 0 | 8 | Small-medium: font glyph outlines (`GetGlyphOutlineW`, kerning, `AddFontResourceExA`); CoreText |
| `SHLWAPI`/`SHELL32`/`RPCRT4`/`VERSION`/`COMDLG32`/`COMCTL32`/`urlmon` | 37 | 4 | 0 | 33 | Small each (path helpers, special folders, UUIDs, version info; file dialog/urlmon likely editor-only) |
| `LocalisedStrings.dll` | 5 | 0 | 0 | 5 | Small: lift as a third module (it needs the same CRT HLE) or HLE its 5 calls |
| `PhysXLoader` / `PhysXCooking` | 5 | 0 | 0 | 5 | **Lift, not HLE:** add PhysXLoader/Cooking/Core/Device (old MSVC, no TLS) as modules; only `cudart32_30_9` + WSOCK32 + IPHLPAPI to HLE (CUDA: report no device) |
| `XINPUT1_4.dll` | 2 | 0 | 0 | 2 | Trivial: ordinals #2/#3 exist for `xinput1_3.dll`; alias |
| `d3d9`, `DINPUT8`, `WINMM`, `ole32`, `OLEAUT32` | 13 | 13 | 0 | 0 | covered by name (the D3D9 *interface* surface the engine uses is a separate, later measurement) |

Totals for the engine: 823 imports; 209 ok, 95 crt64, 519 missing.

## Go / no-go: milestones 1-2 (2026-11-20, v79.0a)

**GO.** The engine lifts: one multi-module run of the stub plus the 20 MB
engine DLL succeeds in under a minute with no errors, 109,634 functions /
4.8 M instructions, and the output compiles. Nothing found is a
structural blocker for x86recomp:

- Static TLS: present but trivial (8 bytes, compiler-generated, no
  callbacks) and refused only by a runtime check whose x64 counterpart
  already does the work.
- Unimplemented instructions: 6 real SSE2 sites to add to the lifter; the
  other 379 are CPUID-gated SIMD paths or junk decodes (to confirm at run
  time).
- Indirect control flow: switch tables recovered by the lifter; the rest
  are tail calls / import thunks the dispatcher handles.

The risk moves to the runtime: the 32-bit MSVC 2015+ CRT (UCRT +
VCRUNTIME EH + MSVCP140 iostreams) is the largest gap and sits on the
startup path; D3DX's effect framework and fibers are the next two.

## Recommended milestone 3 plan

Goal: the stub + engine reach their first window, with every import
handled by design (no catch-alls), in this order:

1. **Upstream x86recomp, small first:** (a) allow static TLS in lifted
   32-bit DLLs (reuse the x64 slot path; still refuse callbacks);
   (b) SSE2 `paddsw`/`psubsb` (and the rest of that saturating family,
   with `lift_sse_test` coverage); (c) DLL aliases `xinput1_4` -> the
   xinput1_3 handlers.
2. **Startup trace:** a minimal game target (`recomp_add_lifted`,
   `GameConfig::lifted_dlls` = GameManagerVC), run until the first fatal
   unhandled import, and record the imports actually called at startup.
   That ordered list, not the static 519, sizes the work.
3. **32-bit CRT, in the order startup needs it:** VCRUNTIME140 32-bit EH
   (`__CxxFrameHandler3`, `_except_handler4_common`, `_CxxThrowException`
   for x86 ThrowInfo layouts, RTTI casts) on the existing SEH chain; audit
   the 76 crt64 UCRT handlers for 4-byte pointers; stdio/convert/string;
   `_CI*` x87 intrinsics on the exact x87 model. Decide early whether
   MSVCP140 iostreams/locale are HLE with x86 MSVC layouts or something
   else; measure which of the 142 are reached first.
4. **Confirm the SIMD gating** at run time (the ISA globals at
   `0x11BB6D78` / `0x11BB6A18` read SSE2-level values).
5. **Fibers design** upstream (host stack per fiber) once startup shows
   whether they are used before the menu.
6. Then milestone 4 (D3DX: `ID3DXEffect` over fx_2_0 + the bytecode front
   end) and the remaining modules (OpenAL, zlib, Steam bridge, PhysX as
   lifted modules) toward the Scaleform main menu.

## Milestone 3 step 1: upstream x86recomp changes (committed 2026-11-20)

Branch `metal-rails/m3-step1` from `2461249e`, three SSH-signed commits
(`17aef3f`, `72846ac`, `2b5e819`), pushed to the fork
github.com/ianjackson8/x86recomp; `X86RECOMP` now pins `2b5e819`.
Three independent changes (each applies alone to `2461249e`):

1. **Static TLS in lifted 32-bit DLLs** (`process.cpp`, `runtime.h`,
   ARCHITECTURE.md): the `!p.x64` refusal is removed; the existing slot
   path (index after the EXE's, per-thread template copy, 32-bit TEB
   `fs:[0x2C]`) now serves both. TLS callbacks are still refused. No unit
   test exists for DLL static TLS (x64 neither); the startup trace is its
   first real test.
2. **SSE2 saturating integer arithmetic on XMM** (`emit.cpp`, `sse.h`):
   `paddsb/w`, `paddusb/w`, `psubsb/w`, `psubusb/w` (the MMX path had them;
   the XMM path fell to `Unimpl`). Re-lift of this game: exactly the 6
   sites change (`Unimplemented` -> 4x `AddSat<int16_t>`, 2x
   `SubSat<int8_t>`), unimplemented 385 -> 379, nothing else differs.
3. **`xinput1_4.dll` -> `xinput1_3.dll`** in `NormaliseDll` (same
   ordinals #2/#3/#4 and signatures).

Tests (M5 Pro, macOS 27.0):
- x86recomp standalone debug build: 563/563 steps, **ctest 45/45 pass**
  (none of them reaches the new code on arm64).
- `lift_sse_test` (x86-64-host oracle) run under **Rosetta 2**, built as
  x86_64 by a scratch wrapper (no x86recomp changes): non-PIE,
  `-pagezero_size 0x1000`, and a zero-fill `__KBUF` segment at
  `0x200000` that owns the native buffer's range (Rosetta maps its AOT
  image right after the binary, which otherwise takes it).
  - This game's 4 new forms: 0 failures over 20,000 trials each.
  - Synthetic image with all 8 mnemonics x 5 operand shapes (reg/reg,
    same reg, `[eax]`, `[ecx+0x10]`): 40 forms, 800,000 checks, 0 failed.
  - Mutation check (saturation replaced by wrap-around): every one of the
    8 mnemonics fails; restored file byte-identical and passing.
  - All 2,020 implemented forms of this game (52 unimplemented SSSE3+/AVX
    forms filtered out, as the harness aborts on the first):
    4,040,000 checks, 5 forms fail (`fisttp [esp]`, `rcpps` x2,
    `vmovdqu` with ymm x2). The **pristine `2461249e`** run of its 2,016
    forms fails the identical 5, so they are pre-existing, not
    regressions. Causes not investigated: RCPPS precision is
    implementation-defined (Rosetta's need not match the modelled
    table); `fisttp` and the ymm stores are suspected harness/state
    limits under Rosetta, unverified.

## Milestone 3 step 2: startup trace (2026-11-20)

x86recomp `2b5e819`, re-lift: 379 unimplemented sites (was 385). Game
target `railworks` (`src/main.cpp`: `GameConfig` with
`lifted_dlls = {"plugins\\GameManagerVC.dll"}`, guest dir
`C:\Program Files (x86)\Steam\steamapps\common\RailWorks`), linked with
`recomp_runtime`, `recomp_d3d9`, `recomp_xinput`, `recomp_dinput8` only.
`recomp_ucrt` is deliberately **not** linked: its handlers are x64-only
and would bind and misbehave silently on this 32-bit guest. Release build
1 min 46 s wall (764 steps), binary 143 MB.

Run (`RAILWORKS_TRACE=1`, `logs/startup-trace.log`):
- Both modules map (no `--base`); 613 imports unbound at load (the static
  gap plus the CRT); `xinput1_4` binds (alias works).
- The stub's `mainCRTStartup` calls `GetSystemTimeAsFileTime`,
  `GetCurrentThreadId`, `GetCurrentProcessId`, `QueryPerformanceCounter`
  (security cookie), `IsProcessorFeaturePresent`, then stops:
  **`FATAL: unimplemented import ucrtbase.dll!_initterm_e`** (return
  address `0x004016F6`, stub). The engine DLL is never loaded.
- So the first blocker is the 32-bit UCRT, in the 5 KB stub. Next unit of
  work: the stub's 28 UCRT/VCRUNTIME imports correct for 32-bit guests,
  until the stub reaches `LoadLibrary("plugins\\GameManagerVC.dll")`.

## Milestone 3 step 3: 32-bit CRT, first pass (2026-11-20, in progress)

Upstream work on branch `metal-rails/m3-crt32` of the fork (worktree
`vendor/x86recomp-crt32`, stacked on `m3-step1`): four signed commits
`17b2c36` (per-width HLE audit), `76abf1c` (CRT for 32-bit guests),
`ee86d4c` (rpcrt4/shlwapi/DosDateTimeToFileTime), `d45387a` (Steam
bridge, first stage); each builds and passes its ctest (45, 46, 47, 47).
`X86RECOMP` still pins `2b5e819`; the game builds against the branch in
`out/build/crt32` (`-DX86RECOMP_DIR`). Two new portable tests: `ucrt_fp`,
`shlwapi_path`.

x86recomp changes:
- **Two-sided HLE audit:** `Def::x86` + `HLE64_ONLY`; a 32-bit call into a
  handler audited for x64 only is fatal and named (the mirror of the
  existing x64 guard). Every UCRT/MSVCP140/VCRUNTIME handler starts as
  `HLE64_ONLY` and is promoted to `HLE64` once audited for both widths;
  `recomp_ucrt` is then safe to link for 32-bit guests (metal-rails links
  it only when the x86recomp tree has `HLE64_ONLY`).
- Pointer-width aware: `GuestStrings`, onexit tables, `_initterm(_e)`,
  argv/environ, `__std_exception_copy/destroy`, `__current_exception*`,
  `StrTo` (endptr), `type_info` compare.
- `ArgD/ArgF/RetD/RetF` width-aware: 32-bit doubles from stack slots,
  results pushed exactly onto the x87 stack (`LoadF64/F32`).
- printf: 32-bit `va_list` (4-byte slots, 8 for 64-bit ints and doubles),
  `%p` 8 digits, `%z/%t/%I` 32-bit; the `__int64 options` argument's two
  slots.
- New: `_controlfp_s` (x87 CW + MXCSR, `ucrt_fp.h`, unit-tested on
  documented constants, mutation-checked), `_isnan`, `strncat`, a string /
  wide-string / ctype batch ("C" locale), `srand`, `_getcwd`,
  `__std_type_info_name` (undname formatting via `UndnameTypeName`; all
  2,930 engine RTTI names demangle, **not yet diffed against Microsoft's
  output**), rpcrt4 UUID functions, 7 shlwapi path helpers
  (`shlwapi_path.h`, unit-tested on the documentation's examples),
  `DosDateTimeToFileTime`. ~110 handlers audited/promoted for 32-bit.

metal-rails changes: two more lifted modules, both relocated because they
share the engine's preferred base `0x10000000`:
- `LocalisedStrings.dll` (SHA-256 `750cab94...b1d2`) at `0x12000000`:
  375 functions; the engine loads it lazily and binds 5 functions with
  GetProcAddress (a refused LoadLibrary left null pointers: "indirect
  branch to 00000000").
- `zlibwapi.dll` (zlib + **minizip**, SHA-256 `9f8729ac...bf90`) at
  `0x12100000`: 526 functions; the engine and LocalisedStrings import
  minizip by ordinal (#61-72 `unz*`, #80-84 `zip*`, #100/127/128), so it is
  lifted rather than reimplemented. Its 67 KERNEL32 imports were all
  covered already. 39 new unimplemented sites are inflate's message
  strings and bit-mask tables in `.text` (junk decodes).
- Lift: 4 modules, 110,535 functions, 4.85 M instructions, 419
  unimplemented sites (379 + 1 `xgetbv` + 39 zlib data), 59 s.

Trace now (`logs/startup-trace-crt32.log`), 102 distinct imports:
stub CRT startup -> `_controlfp_s(NULL, _PC_53, _MCW_PC)` -> WinMain
(single-instance check, plugin search) -> `LoadLibraryA` -> DllMain of
zlibwapi, LocalisedStrings, GameManagerVC (CRT init, RTTI names, SRW locks,
UUIDs) -> engine startup: path setup (shlwapi), file mapping,
LocalisedStrings reads `Languages\en.lan` (252,196 bytes) -> **stops at
`steam_api.dll!SteamAPI_RestartAppIfNecessary`**.

Known runtime issue (pre-existing, x86recomp): after a fatal on a deep
host stack, `FatalReport`'s `backtrace()` faults (`__thread_stack_pcs`),
giving a second "SIGSEGV ... (runtime bug)" report. The first fatal is
the real one.

## Steam bridge, first stage (2026-11-20)

- SDK: **Steamworks 1.53a** (user's download, outside the repo;
  `STEAMWORKS_SDK` in `tools/local.env`). Its headers declare all ten
  interface versions the game's `steam_api.dll` was built with
  (`SteamClient020`, `SteamUser021`, `SteamFriends017`, `SteamUtils010`,
  `STEAMAPPS008`, `STEAMUSERSTATS012`, `SteamInput006`,
  `SteamController008`, `STEAMUGC016`, `STEAMREMOTESTORAGE016`); its
  `libsteam_api.dylib` is universal (i386, x86_64, arm64). SDK 1.65's
  versions are all one step newer, so 1.53a serves as headers and library.
- Native probe (arm64, Steam running): `SteamAPI_Init` with
  `SteamAppId=24010` succeeds; the client serves all six old versions;
  `BLoggedOn` 1, `GetAppID` 24010, `BIsSubscribedApp(24010)` 1, language
  english, 81 DLC. libsteam_api prints the user's Steam ID to stdout during
  init, so game logs contain it (`logs/` is untracked).
- Verified from the engine binary: the guest's `CCallbackBase` vtable is
  MSVC's `{Run(void*, bool, SteamAPICall_t), Run(void*),
  GetCallbackSizeBytes}` (overloads reversed); a `CCallback<T,P>` is vptr,
  flags +4, `m_iCallback` +8, object +0xC, member function +0x10.
- Generated vtables (x86recomp `tools/steam_vtables.py`, MSVC order) agree
  with the game's `steam_api.dll` flat exports for all 118 checked slots.
- Callback structs: macOS libsteam_api packs them to 4, the Windows guest
  to 8; translation still to write. The engine registers 12 callback types
  and 26 call-result uses (Workshop/UGC, RemoteStorage, HTTP, leaderboards,
  stats, overlay, DLC installed), so more interfaces than the six
  (ISteamUGC, ISteamRemoteStorage, ISteamHTTP) will be needed.
- Trace: `SteamAPI_RestartAppIfNecessary` -> 0, `SteamAPI_Init` -> 1
  (client loaded, ownership confirmed), `SteamAPI_RegisterCallback`, then
  the engine continues to `_time64` (HLE64_ONLY: next CRT item).

## Milestone 3: trace to the first window (2026-11-20)

x86recomp branch `metal-rails/m3-crt32` on the fork, now at `6fd46ba`
(signed commits after `d45387a`: `8f7b961` Steam callback repacking,
`c11fdeb` UCRT time/conversion/wide printf/error handlers, `625ec5c` INI
files and W window functions, `af0cffd` CryptoAPI, `8d29a25` Steam
interface methods, `6fd46ba` file bitmaps and GetObjectA); every commit
builds and passes its ctest (47-50). `X86RECOMP` still pins `2b5e819`.

Steam callbacks: libsteam_api delivers structs packed to 4, the guest wants
8. `tools/steam_callbacks.py` has clang lay the 1.53a headers out for
`i686-pc-windows-msvc`: 186 callback structs (14 HTML-surface ones with
pointers left out); all 27 the engine registers are covered, and their
guest sizes equal the engine's own `GetCallbackSizeBytes` constants (MSVC's
`sizeof`), 27 of 27.

The trace, in order (`logs/startup-trace-crt32.log`, ~182 distinct
imports), after Steam init:
- Engine setup: `_time64`, string building, `GetSystemInfo`, module path,
  `_wtoi`/`iswdigit` (command line or version parsing), wide `swprintf`.
- **CrashRpt** (statically linked crash reporter): reads
  `data\CrashReport\Win32\crashrpt_lang.ini` (GetPrivateProfileStringW),
  `LoadLibraryW`/`FreeLibrary`, creates its directory, a GUID
  (`CoCreateGuid` + rpcrt4 string), an event and a file mapping, then
  installs every CRT error handler (`_set_error_mode` ... `set_unexpected`).
- Steam: `ISteamUser::GetSteamID`; a **CryptoAPI** round (PROV_RSA_FULL
  verify context, MD5 of data, RC4 key derived from it, `CryptEncrypt`);
  `ISteamClient` (`SetWarningMessageHook`),
  `ISteamUtils::SetOverlayNotificationPosition`,
  `ISteamApps::GetCurrentGameLanguage`.
- **First window: the splash.** `LoadImageA(NULL,
  "data\textures\frontend\TSC Splash Screen x32.bmp", IMAGE_BITMAP, 0, 0,
  LR_LOADFROMFILE)` (600x200, 32-bit BI_RGB, bottom-up), `GetObjectA` (24-byte
  BITMAP), `RegisterClassA("railworksinit")`, `GetSystemMetrics`,
  `CreateWindowExA(WS_POPUP, 600x200 at 212,284)` with a child
  `STATIC` (`WS_CHILD|WS_VISIBLE|SS_BITMAP`, given the bitmap with
  `SendMessageA`), `ShowWindow`, `UpdateWindow`, then the message pump
  (`PeekMessageA`). The window is created and shown but **blank**: x86recomp's
  GDI is query-only, so the static control paints nothing.
- Next stop after the splash: `kernel32!GetFileAttributesExA`.

Decisions recorded in the code (all named fatals where not modelled):
- CRT error handlers are recorded and returned, never called (the
  conditions are fatal errors here).
- Steam's warning hook is not called (the client may call it on any
  thread); warnings go to stderr.
- `iswdigit/iswspace/iswalnum`: exact for ASCII, fatal beyond it.
- CryptoAPI: RC4 128-bit default key (Microsoft Strong provider) = the MD5
  hash; other key lengths fatal.
- wprintf `_p` forms: positional arguments fatal until supported.

## Stopped: fibers (2026-11-20)

After the splash, `GetFileAttributes(Ex)A` (x86recomp `a163f5c`), the engine
calls `kernel32!ConvertThreadToFiber` (return `0x10611555`) on the main
thread. Its fiber use is one small class (2 call sites each for
ConvertThreadToFiber, CreateFiber, SwitchToFiber, DeleteFiber): init
(`0x10611530`) is `CreateFiber(size, 0x106115C0, this)` or, with no size,
`ConvertThreadToFiber(this)`, the handle at `+0x14`; the start routine
calls a virtual method then switches back; teardown is DeleteFiber. How
often it switches is not known until it runs.

Lifted code runs guest functions as host functions, so a fiber needs its
own host stack as well as its guest stack (and TEB FiberData at fs:[0x10],
StackBase/Limit). Options:
- ucontext (`makecontext`/`swapcontext`) in the platform layer: same host
  thread, so thread identity, thread-locals, x87/SSE state and TLS stay as
  on Windows; cheap switches. Tested on this Mac (arm64, macOS 27): works
  (4 MB stack, thread_local intact, deep recursion, a C++ exception thrown
  and caught inside the fiber), but Apple marks the API deprecated, "No
  longer supported".
- One host thread per fiber with a strict hand-off (only one runs): no
  deprecated API, but the guest-visible thread (TEB, id, TLS, last error,
  per-thread runtime state) must follow the logical thread across host
  threads; each switch costs a thread hand-off (microseconds).
- A hand-written context switch: against x86recomp's no-assembly rule.
