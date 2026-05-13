# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This is an **archival mirror** of DOS/32 Advanced DOS Extender v9.12 (released 2006-04-20 by Narech Koumar), preserved here for historical reference after the original site went offline. The release was unzipped over the v8.00 "Liberty Edition" tree (from Sourceforge), so this repo bundles v9.12 binaries/sources with v8.00's docs and examples.

Treat the source as a historical artifact. The primary downstream consumer is the sibling project `dos-rs/` (`/Users/tbeck/src/dos/dos-rs/`), which uses `dos32a.exe` as the protected-mode-extender stub it prepends to its emitted LX executables.

## How to rebuild dos32a.exe

The repository ships a containerized build that runs **headless DOSBox + Borland TASM 5 + TLINK 7** against the unmodified 2006 assembly source. The original DOS/Windows toolchain runs unchanged inside the emulator — no source patches, no assembler porting.

```sh
make image    # one-time: build the container image (Ubuntu 26.04 + dosbox)
make build    # produce out/dos32a.exe
make run      # smoke-test the rebuilt stub under dosbox-x (host-side)
make shell    # bash shell inside the container, for poking at TASM/TLINK
```

The build is **linux/amd64-only** (dosbox is x86_64). On Apple Silicon, Docker Desktop runs it under Rosetta 2.

Output: `out/dos32a.exe`. The 2006 reference binary at `binw/dos32a.exe` is intentionally left untouched as a regression oracle. **Don't overwrite `binw/`** — that's the gold copy.

### How the container build is structured

| File | Role |
|---|---|
| `Makefile` | Host-side ergonomic wrapper (`make image` / `build` / `shell` / `run` / `clean`). |
| `Dockerfile` | `ubuntu:26.04 + dosbox + xauth`. Exec entrypoint is `/app/dosbox.sh`. |
| `dosbox.sh` | `mkdir -p /app/out`, then `SDL_VIDEODRIVER=dummy dosbox make.bat -config=./conf/dosbox.conf -exit`. |
| `conf/dosbox.conf` | DOSBox config; `[autoexec]` mounts `/app` as DOS drive `D:` and runs `make.bat`. |
| `make.bat` (top-level) | `cd src\dos32a && make.bat` inside DOSBox. |
| `src/dos32a/make.bat` | Calls `..\..\bin\tasm32` + `..\..\bin\tlink`. Output: `..\..\out\dos32a.exe`. |
| `bin/TASM32.EXE`, `TLINK.EXE`, `RTM.EXE`, `32RTM.EXE`, `DPMI16BI.OVL`, `DPMI32VM.OVL` | Vendored Borland tools. Cherry-picked from `dos32a-ng@880be04`. |

The DOSBox + TASM/TLINK harness was cherry-picked from `yetmorecode/dos32a-ng` (see commits `bec2b0c` and `56f7b88` for provenance — both carry `(cherry picked from commit …)` trailers). That repo's `main` branch also has a VXD-fixup-support patch in the loader; we deferred it because dos-rs's linker doesn't emit VXD-style SRCLIST fixup records.

### Using the rebuilt stub from dos-rs

dos-rs's `Makefile` accepts a `STUB=` override. To validate end-to-end:

```sh
cp out/dos32a.exe /Users/tbeck/src/dos/dos-rs/vendor/dos32a/dos32a.exe.rebuilt
cd /Users/tbeck/src/dos/dos-rs
STUB=vendor/dos32a/dos32a.exe.rebuilt make in-docker
dosbox-x -fastlaunch -exit \
    -c "mount c $(pwd)/target/dos/debug" \
    -c "c:" \
    -c "hello.exe > hello.out"
cat target/dos/debug/hello.out   # expect the two-line Hello + FreeMemInfo output
```

The path must be relative to dos-rs's repo because that container only mounts dos-rs's own directory.

### Linker note: TLINK vs WCL

The 2006 release linked with Watcom `wcl`; our container build uses Borland `tlink`. Both produce working DOS MZ executables that dos32a's loader is happy with. The rebuilt binary is `~27.9 KB` vs the 2006 reference's `~27.5 KB` — same code, slightly different linker metadata.

If byte-identical-to-2006 output is ever required, we'd need to install Watcom C/C++ 11.0 in the container alongside DOSBox and switch `src/dos32a/make.bat` back to using `wcl`. That has not been done; the functional round-trip test (`make run` in dos-rs) is the validation that matters.

## Original DOS-host build (historical reference)

The 2006 build scripts (`src/setvars.bat`, `src/makeall.bat`, `src/*/make.bat`) are still in the tree and still work if you have **Borland TASM 5.0** + **Watcom C/C++ 11.0** on a real DOS/Windows machine. The container build above subsumes them for development on a modern host. The two flows produce structurally equivalent binaries.

The original scripts expect these vars (set by `src/setvars.bat`):
- `TASM` (TASM root, has `BIN/tasm32.exe`)
- `WATCOM` (Watcom root, has `BINNT|BINW|BINP`)
- `DOS32A` (this repo root)
- `TASMFLAGS`, `WCLFLAGS`
- `PATH`, `INCLUDE`, `EDPATH`

`makeall.bat` walks every component; each `make.bat` calls `src/sutils/build/build.exe` to bump build numbers, so on a fresh checkout the build utility must be built first.

## Code architecture

### Two-segment extender (Kernel + Client)

DOS/32A's main executable is split into segments **assembled separately and linked together**:

- `_ID32` (0x80 bytes) — configuration header (copyright, timestamp, flags) edited by SS.
- `_KERNEL` — built-in DPMI host, CPU/FPU/system-type detection, INT 31h services. Source: `src/dos32a/kernel.asm` + `src/dos32a/text/kernel/{detect,exit,init,int31h,intr,misc,mode,test}.asm`.
- `_TEXT16` ("Client") — extender duties: app loader (LE/LX/LC/PE), INT 10h/21h/33h emulation, config UI. Source: `src/dos32a/dos32a.asm` + `src/dos32a/text/client/{config,data,debug,int10h,int21h,int33h,misc,strings}.asm` and `loader.asm`, `loadlc.asm`, `loadpe.asm`.
- `_STACK` (0x800) — local stack, also doubles as scratch buffer for the loader, mouse callbacks, local DTA, and mouse shape buffer (see layout in `src/dos32a/notes.txt`).

Kernel and Client are **independent** and communicate through a small internal API (`pm32_info`, `pm32_init`, `pm32_data` are the externs in `dos32a.asm`). In theory either side can be replaced without modifying the other. When DOS/32A detects an external DPMI host, it **copies the Client over the Kernel** to reclaim conventional memory — this self-overwriting design is fundamental and is why the layout matters.

### Memory-reuse hazards

The extender reuses memory occupied by one-shot initialization code as data storage after that code has executed. Reused-area labels to watch for:

- Kernel: `@area1_db`, `@area1_dw`, `@area1_dd`, `@callback_data`
- Client: `@area1_*`, `@area2_*`

`src/dos32a/notes.txt` and `src/dos32a/text/include.asm` are required reading before moving any routine around. Always inspect TASM listing files (`/la` flag in `make.bat` emits them) when modifying assembly — the byte-for-byte layout is load-bearing.

### Companion tools

The 2006 release shipped six companion utilities. Our container build currently only produces `dos32a.exe` (it's all dos-rs needs). The utilities are still buildable via the original `make.bat` scripts under the historical DOS-host flow.

- **SB** (SUNSYS Bind) — binds extender into stub.
- **SC** (SUNSYS Compress) — LE/LX → LC converter; can embed `oemtitle.inf` (≤512 bytes ASCII) as proprietary version-info readable by SB/SVER.
- **SD** (SUNSYS Debugger) — pure assembler; uses DOS/32A's ADPMI extensions, so it **only runs under DOS/32A's built-in DPMI** (not under Windows DPMI). Disassembler covers 80486+80487 only.
- **PCTEST** — mode-switch benchmark using the PIT.

### Configuration profiles

`d32/*.d32` are pre-built configuration overlays (`default.d32`, `dos4gw.d32`, `failsafe.d32`, `maximum.d32`, `minimum.d32`, `pmodew.d32`, `standard.d32`, `verbose.d32`) consumed by SB/SS to retarget the `_ID32` header without recompiling.

## Things to know when editing

- This is the v9.12 source dropped on top of v8.00's tree. If you see references to v8.00 in older docs (`readme.1st`, `docs/`) and v9.12 in newer ones (`ChangeLog`, `updates.txt`, top-level `readme`), that mismatch is intentional and not a bug to fix.
- `src/_todo.txt` and `src/dos32a/changes.txt` are the author's own working files — useful context, not to be cleaned up.
- `.gitignore` excludes `*.obj/*.exe/*.lib/*.map/*.exp/*.pch/*.dll/*.lst` everywhere **except** `binw/`, `examples/`, `l32/`, and `pctest/` (which carry committed binaries from the v9.12 release) and `bin/` (vendored Borland TASM/TLINK — `*.EXE` allowed there via gitattribute).
- Source assembly files require `STDDEF.INC` (in `src/sutils/misc/`) and the C side requires headers from `h32/` (`typedefs.h`, `debug.h`, `d32a.h`).
- The container build will leave intermediate `*.LST` files inside `src/dos32a/` after a run; `make clean` removes them along with `out/`.
- The `dos32a-ng` upstream remote (`https://github.com/yetmorecode/dos32a-ng.git`) is configured for pulling future improvements. Their `main` has a deferred VXD-fixup commit (`bf28a94` + `24a75e8`) that we may want later if we ever load non-Watcom LX executables.
