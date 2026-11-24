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

## Fibers (2026-11-20)

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

Decision (user): ucontext on the same thread. Implemented in x86recomp
`290a61c` (platform host contexts + kernel32 fibers; host_context_test).
The engine's fibers then run: ConvertThreadToFiber on the main thread,
CreateFiber, a worker CreateThread, SwitchToFiber, and startup goes on.

## Milestone 3 done: D3D9 device created (2026-11-20)

x86recomp `metal-rails/m3-crt32` at `b7b6039` (`a163f5c`
GetFileAttributesExA, `290a61c` fibers, `b7b6039` MonitorFromWindow /
GetMonitorInfoA); ctest 51/51 at each commit.

After the fibers: COM + WMI hardware queries (CoCreateInstance,
IWbemLocator::ConnectServer, CreateInstanceEnum), GlobalMemoryStatusEx,
then the renderer:
- `Direct3DCreate9(32)`, `GetAdapterIdentifier`, `GetAdapterModeCount` /
  `EnumAdapterModes`, `AdjustWindowRect`, `MonitorFromWindow` /
  `GetMonitorInfoA`.
- **Main window:** class `railworks`, title "Train Simulator", WS_POPUP
  640x480, then `SetWindowPos`.
- `CheckDepthStencilMatch`, `CheckDeviceMultiSampleType`,
  **`IDirect3D9::CreateDevice` -> D3D_OK**: 3024x1964 (the host's native
  mode, from the enumerated modes), D3DFMT_A8R8G8B8, fullscreen, auto
  depth D3DFMT_D24S8, D3DPRESENT_INTERVAL_IMMEDIATE, behaviour 0x40
  (hardware vertex processing) without FPU_PRESERVE, so the x87 goes to
  single precision (CW 027F -> 007F) as on Windows. Backend: x86recomp's
  generic `SDL_GPU (metal)`.
- Then `GetRenderTarget`, `GetDepthStencilSurface`, and the next stop:
  **`IDirect3DDevice9::CreateStateBlock`** (milestone 4, the renderer).

## Milestone 4 (in progress, 2026-11-20): to D3DX

- `X86RECOMP` pinned to `metal-rails/m3-crt32` `b7b6039` (`df90e80`); the
  default build reads `STEAMWORKS_SDK` from `tools/local.env`.
- **Renderer: x86recomp's own Metal device** (Liberty's), the default via
  `RAILWORKS_GFX=metal` (`6a53472`): "gfx: Metal (Apple M5 Pro)", back
  buffer 3024x1964. Its shader caches (`~/Library/Caches/x86recomp`) are
  shared by every game on the runtime and keyed by content: GTA IV's 603
  shaders / 380 pipelines load but are never used here (at most prewarm
  time).
- x86recomp branch `metal-rails/m4-render` (fork; `2368fd6` D3D9 state
  blocks, `724412f` RTTI casts with rtti_test, `aea7955` aligned
  allocation; each builds, ctest 51-52).
- `tools/complete_jumptables.py` (`2a963dc`, own code): one engine switch
  (`10EE47EE`) had no bounds check and an empty Ghidra table.
- Trace after CreateDevice: CreateStateBlock, GetDeviceCaps, CreateQuery,
  `dynamic_cast`, a vertex declaration and shader, textures (created,
  locked, filled), `typeid`, then **`d3dx9_43!D3DXCreateBox`** (an
  ID3DXMesh).

D3DX: the engine uses 38 functions (ID3DXEffect over fx_2_0 binaries,
meshes, sprite, font, line, texture loading, shader compile/assemble).
Microsoft's `d3dx9_43.dll` (x86, 2 MB, 1.8 MB code) is on this Mac in the
Steam client's DirectX redistributable (`Steamworks Shared/_CommonRedist/
DirectX/Jun2010/Jun2010_d3dx9_43_x86.cab`, with D3DCompiler_43). Its
imports: msvcrt.dll 85 (x86recomp has no msvcrt HLE), KERNEL32 76 (7
missing), GDI32 27 (16 missing: glyph outlines, DIB sections, text),
ADVAPI32 3 (1 missing). Decision needed: lift it, or reimplement D3DX.

## Milestone 4: Microsoft's D3DX lifted (2026-11-24)

Decision (user): lift Microsoft's `d3dx9_43.dll` from the player's own
Steam DirectX redistributable, not reimplement D3DX.

- `tools/redist.sh` extracts it (SHA-256 `0b28546b...`, pinned) from
  `Steamworks Shared/_CommonRedist/DirectX/Jun2010/Jun2010_d3dx9_43_x86.cab`
  to `<data>/redist/d3dx9_43.dll` (`~/Library/Application Support/
  railworks/redist` on macOS). Never in the repo. `src/main.cpp` lifts it
  at `0x12200000` (after LocalisedStrings and zlibwapi) from there
  (`LiftedDll::host_path`, x86recomp); the game exits with a message if it
  is missing. Ghidra: 4,606 functions; the lift finds 5,914.
- Its data sits in `.text` (no `.rdata`): ~3,000 junk decodes of data
  bytes, all outside Ghidra's function bodies. Harmless (never reached);
  a lifter option to skip data-pointer entries in such images is a
  follow-up.
- Build cost. One D3DX function (`1228148D`, ~97k instructions, its HLSL
  compiler; 512k lines of C++) cannot be one host function: optimised it
  ran > 1 h; at -O0 arm64 GlobalISel's CSE and then branch relaxation
  never finished, and the result was > 1 MiB, so branches were out of
  range ("fixup value out of range"). x86recomp `--split-above` (new)
  emits it as 7 parts in files `gen_d3dx9_43_075_<n>.cpp`; `tools/lift.sh`
  passes `--split-above 12000` (only this function; the engine has
  none that big). The rest of the slow build is straight-line x87 code:
  runs of ~10k x87 instructions (`D3DXSHMultiply6` at `1223E081`, parts
  of `1228148D`) are one block each, and SLP vectorisation, CSE, SROA
  and the like are super-linear in a block's size: ~1.5 h for 2 files on
  the first build (cached after). Follow-up upstream: cap x87 run length
  in the lifter.
- CPU dispatch: D3DX jumps through a table of function pointers in
  `.data` (`123CA068..123CA18C`, 74 slots, 124 `jmp [slot]` sites) that
  the first call repoints to the SSE/x87 implementation. Ghidra exports
  each as a one-entry jump table (the slot's initial value); x86recomp
  now ignores such "tables" for writable slots, so they dispatch.
- Imports added upstream: `msvcrt.dll` (aliases to the UCRT handlers
  plus msvcrt's own: operator new/delete, `_onexit`/`__dllonexit`,
  `_lock`, `_controlfp`, `_clearfp`, the `_CI*` x87 intrinsics, legacy
  `_snprintf` family, ...), `RegOpenKeyA`, shader `GetDevice`,
  `ValidateDevice`, recorded state blocks (`BeginStateBlock`, used by
  ID3DXEffect), and the engine's own `_libm_sse2_*_precise` maths
  (arguments and result in xmm0).

Trace (612k lines): D3DX initialises, effects compile and record their
state blocks, the engine builds geometry, then **`cFontRenderer`**
(engine, vtable `10FED838`) creates an `ID3DXFont`: D3DX's font code
needs real GDI text (`GetCharABCWidthsI` via GetProcAddress, then
`CreateFontIndirectW`, `GetTextMetricsW`, `CreateDIBSection`,
`ExtTextOutW`, `GetGlyphOutlineW`, ...). x86recomp's GDI text functions
are stand-ins that draw nothing, so `D3DXCreateFont` fails; the engine
does not check the result and calls `PreloadCharacters('!', '~')` through
a stale local (the `cFontRenderer` itself): "indirect branch to CC0000C2
from 107CA269". Decision needed: how GDI renders text (font engine and
font source).

Decision (user, 2026-11-24): GDI text on CoreText. x86recomp now has a
host font engine (`runtime/host_font.h`, CoreText on Apple) and real GDI
fonts, DCs and DIB sections. D3DX's font path, as traced: optional GDI
entry points by GetProcAddress (`GetCharABCWidthsI`, `GetCharWidthI`,
`GetFontUnicodeRanges`), Uniscribe (`usp10.dll`) tried and skipped when
absent, then `CreateFontIndirectW`, `CreateDIBSection`,
`GetCharacterPlacementW` for glyph indices, and one `ExtTextOutW`
(ETO_GLYPH_INDEX) into the DIB per glyph (188 at startup). The engine's
fonts come up from the host's faces of the same names.

After the fonts (trace 636k-995k lines):
- Steam Cloud: `ISteamRemoteStorage` v016 (`FilePersisted`, ...) and
  leaderboards (`FindLeaderboard`), forwarded to the Steam client.
- Lua's protected calls (`luaD_rawrunprotected`, e.g. at `10E2DDDC`) call
  `_setjmp3` from VCRUNTIME140 through an import thunk (`10E2B551`);
  D3DX imports msvcrt's. The lifter now treats imported setjmps as
  setjmp calls (26 new resume entries), and `longjmp` resumes there.
- Lua's first script (`dev/scripts/engineScript.lua`) loads through
  `fopen`/`getc`/`ungetc`.

### msvcp140 lifted (2026-11-24)

Decision (user): lift Microsoft's `msvcp140.dll` rather than write
iostream HLE. The engine uses iostreams/locales (144 msvcp140 imports,
inline template code on MSVC's exact layouts). The game's Steam
redistributables stop at VC++ 2012, so `tools/redist.sh` downloads
`VC_redist.x86.exe` once from Microsoft's versioned URL (SHA-256
`0c09f261...ed64`, the hash is in the URL) and extracts `msvcp140.dll`
14.44.35211.0 x86 (`97e71a3c...8165`) with bsdtar (WiX bundle -> cabinet
-> MSI cabinet). Lifted at `0x12400000`: 2,363 Ghidra functions, data in
`.text` as in D3DX. Its DllMain needed the "C" locale's UCRT data
(`___lc_*`, `__pctype_func`, `_lock_locales`), `setlocale`, and
`_get_stream_buffer_pointers` (answered with an empty buffer, so
`std::filebuf` goes through stdio). The engine then creates a "C" locale
(`_create_locale(LC_NUMERIC, "C")`) for `_atof_l`.

### PhysX 2.x lifted (2026-11-24)

`NxCreatePhysicsSDK` (PhysXLoader) is called during startup, so PhysX is
lifted now rather than at milestone 6: `PhysXLoader.dll` (0x12500000,
247 functions), `PhysXCooking.dll` (0x12600000, 866), `PhysXCore.dll`
(0x12700000, 5,455), the game's own files (hashes pinned). PhysXCore
imports `cudart32_30_9.dll` statically and registers its CUDA kernels at
load (`__cudaRegisterFatBinary` ...): answered as on a machine with no
CUDA device, so GPU physics stays off. Whole lift now: 129,912
functions, 7.25M instructions.

After PhysX: Steam HTTP (`ISteamHTTP` v003, a request at startup), then
**OpenAL** (`alGetError` first). Decision (user): OpenAL 1.1 on
x86recomp's own mixer (in progress). Trace: 1.14M lines.

### Into the main loop (2026-11-24)

- **OpenAL** works on x86recomp's mixer (`recomp_openal`): the engine
  opens the device, probes the source limit (generates until
  AL_OUT_OF_MEMORY at 256, deletes them), then plays.
- The engine registers its UI fonts privately (`AddFontResourceExA`,
  FR_PRIVATE) from `data/font` (Exo, Aura, Bree Serif, FZSSJW): CoreText
  process-scope registration.
- After Steam friends/HTTP/DLC queries the engine reaches its message
  loop (`PeekMessageA`) and D3DX's sprite/font setup.
- **Correction to CLAUDE.md ("none are shipped"): SilverLining's DLLs are
  shipped**, in `data/SilverLining/{vc14,vc143}/{win32,x64}/`. The 32-bit
  engine loads `data\SilverLining\/VC143/win32/SilverLiningDirectX9-MT-DLL.dll`
  (49 KB, 137 exports: the D3D9 renderer; the sky model is in the
  engine). Without it the engine tore everything down and exited 0 after
  ~30 s with no frame. Now lifted at `0x12B00000` (hash pinned; empty TLS
  callback list). It needs `SetPrivateData` and **volume textures**
  (`CreateVolumeTexture`), which x86recomp's renderer does not have yet:
  next.
- Running without `RAILWORKS_TRACE` takes ~30 s to that point; traced, the
  import log is ~4 GB (113M calls), and the hang watchdog reports the
  tracing itself (the main thread busy printing).

## Milestone 4 reached: the Scaleform main menu (2026-11-24)

The launch screen (Academy / Main Menu tiles) and the main menu with the
Dovetail Live login draw natively on Metal, text in the game's own
faces, pointer and clicks working. What it took after the main loop:

- **Anti-tamper check on steam_api.dll** (main loop setup, `104D32D7`):
  `GetModuleHandleA("steam_api")` (the name XOR-hidden, key `0x1265ABF6`),
  `GetModuleFileNameA`, a hash of that file against a digest hidden in
  the engine (`0x111752C8`, XOR `0x72686B28`), and
  `ISteamApps::BIsSubscribedApp(24010)` from the client. Success leaves
  the loop counter at 16; failure makes it count down from 15 and the
  game quits after its first frames (no message). x86recomp returned 0 for
  bridged DLLs' module handles; with the user's approval it now answers
  as Windows (a handle for every imported DLL; the file name is the
  game folder's genuine `steam_api.dll`). Ownership still comes from the
  Steam client; no game code is patched.
- Scaleform's font provider uses GDI: `AddFontResourceExA(FR_PRIVATE)` on
  `data/font`, `EnumFontFamiliesExW`, `CreateFontW`, `GetKerningPairsW`,
  `GetGlyphOutline(GGO_NATIVE)` (which must be quadratics: the faces are
  CFF), and draws its own glyphs.
- Startup also reads Workshop subscriptions (`ISteamUGC`), mapped through
  a read-only mount of the library's `steamapps/workshop`.
- **RailWorks.exe is large-address-aware**; `game.large_address` gives it
  ~4 GiB as on 64-bit Windows. The x86recomp stress mode
  (`RAILWORKS_TOP_DOWN=1`) currently fails early: `ERROR: Could not create
  effect vertexcolour.fx` (cHcEffectDx.cpp:177), so something in the
  effect path mishandles addresses above 2 GiB. To find before long
  sessions reach high memory.
- A run that died while saving left `<data>/drive_c/.../Dovetail Games/
  TS1/DovetailLive.sav` empty; the next start parses it into a garbage
  length and dies in `operator new` (`std::bad_alloc`, uncaught: 32-bit
  C++ exceptions are not modelled yet). Moved aside, a good save is 32
  bytes.
- Pointer: the game reads WM_MOUSEMOVE. x86recomp used its virtual
  cursor for every fullscreen-exclusive window, which drifted from the
  visible pointer; now only while the cursor is hidden or clipped.

## Milestone 5: a scenario loads and drives (2026-11-24)

Free Roam, Cajon Pass in Summer (EMD F7 Warbonnet, Victorville yard, the
scenario where Wine fell to ~6 fps): loads, renders (terrain, track,
rolling stock, sky, HUD), camera keys work, and the train drives; the
user reports it as very smooth throughout (no fps measured yet).

What loading needed beyond the menu:
- Point-light shadow maps (`107E5660`): for each size in a table (largest
  first) a 2D **and** a cube render target in R32F, X8R8G8B8 or R16F;
  with none, the limit at `+0x85C` stays -1, and the setter at `107E2050`
  later indexes record -1 (a memcpy of a garbage count). Needed cube
  render targets in x86recomp.
- Route tiles are named `+000031+000084.bin`, parsed with `sscanf("%d%d")`.
- Two switches the export lacked: one on a loop counter (`10F45D30`, 6
  cases, Ghidra listed 1) and unoptimised ones bounded through a stack
  slot (`1094E333`, 8 cases, and 7 more), both now recovered by the lifter.
- Effects set fixed-function lights (D3DX calls `LightEnable`); x86recomp
  warns that fixed-function lighting with a pixel shader is not emulated.
- `RailDriver.dll` missing is handled (`10BD5B38`: a NULL handle skips the
  controller).

Open:
- **Plain track sometimes missing after a fresh boot** (points drawn,
  plain track not; scenario Restart keeps it so, loading again from the
  main menu draws it). A race in the engine's loading, timing-dependent:
  - every route file is read by one loader thread (`0104`, opens from
    `10EFA157`) in the same order in good and bad boots, and the data is
    identical; what differs is that the main thread (`0100`, through
    D3DX) never creates the `LoftTexDiffSpec.fx.o` effect in a bad boot
    (it does `LoftTexDiff`, `LoftTexDiffTrans`, `LoftBumpTrans`);
  - so the main thread sets up loft materials for the track objects it
    finds while the loader thread builds them, and in a bad boot misses
    the specular one (probably an object seen half built);
  - not memory ordering (it happens with `RAILWORKS_SERIAL=1`), not the
    buffer heap (`RAILWORKS_GPU_HEAP_MB=1024`), not the lifter (a bisect
    seemed to point at one PhysX switch, but the same build then drew
    track: the odds move with timing; bad in 5 of 6 boots with every
    switch recovered, 0 of 6 with fewer, one later boot of each kind).
  Next: find what orders the material set-up after the loader on Windows.
- **PhysX froze** after several minutes of driving: its simulation thread
  (`0108`) loops forever in `f_12737880` (`10037880` in PhysXCore.dll), a
  walk of a pair list of 12-byte nodes with 16-bit next links, which has
  become a cycle; the main thread waits for the step. PhysX's spin lock
  (`1001B6D0`) acquires and releases through Interlocked calls, so that
  lock is not the culprit. One long drive with `RAILWORKS_SERIAL=1` did
  not freeze (not conclusive). Candidate: `RECOMP_TSO` (x86 ordering for
  plain loads and stores in lifted code).
- A "junction switched against train" derailment while track was missing;
  judge only with track drawn.
- `d3dcompiler_43.dll` is asked for 10 times (not provided).
