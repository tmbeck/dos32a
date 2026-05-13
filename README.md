# DOS/32 Advanced DOS Extender

Archival mirror + maintenance fork of DOS/32A, a drop-in DOS/4GW-compatible
DOS extender. Originally written by Narech Koumar (1996–2006). This repo
preserves the 2006 v9.1.2 "Liberty Edition" source release and adds a
containerized build, three clear bug fixes (**v9.12.1**), and DPMI 1.0
support + community VXD loader patch + PCTEST rdtsc upgrade (**v9.12.2**).

> [!NOTE]
> The original site at [dos32a.narechk.net](http://dos32a.narechk.net/) has been
> offline since around 2022; an archived snapshot lives on the
> [Wayback Machine](https://web.archive.org/web/20210726190857/https://dos32a.narechk.net/index_en.html).

## Overview

DOS/32A is a drop-in replacement for the popular DOS/4GW DOS Extender. During
the 1990s many DOS applications and games were built with Watcom C/C++ in
32-bit protected mode using DOS/4GW (Tenberry Software) as their runtime.
DOS/4GW was royalty-free but big, slow, and feature-poor compared to its
commercial siblings. DOS/32A grew up as a free alternative that matched and
exceeded it.

Key features:

- **DOS/4GW ABI-compatible** — runs unmodified Watcom-built protected-mode apps
- **Built-in DPMI 0.9 host** with DPMI 1.0 surface added in v9.12.2 — falls
  back to external DPMI (Windows, OS/2, DOSBox-X, EMM386) when present
- Fast mode-switch and interrupt servicing
- Supports allocation up to **2 GB** of extended memory
- Null-pointer protection, configurable, LE/LX/LC loader, optional
  protected-mode executable compression
- Free under an Apache-style license, no royalties (see [LICENSE](LICENSE))

`DOS/32A` is Copyright © 1996–2006 by Narech Koumar.

## Build

A containerized build runs the original Borland TASM 5 + TLINK 7 toolchain
under DOSBox-X, with Open Watcom v2 for the C compilation steps. Works on
macOS (Apple Silicon native), Linux, and any other host that runs Docker.

```sh
make image     # one-time: build the container (Ubuntu 26.04 + dosbox-x + OW v2 + Borland TASM/TLINK)
make build     # produces out/DOS32A.EXE + 9 utilities + sdebug.lib
make run       # smoke-test the rebuilt stub under dosbox-x on the host
make shell     # bash inside the container, for poking at the toolchain
make clean     # wipe build outputs
```

Output lands in `out/`. The 2006 reference binaries at `binw/` are
preserved untouched as a regression oracle.

See [CLAUDE.md](CLAUDE.md) for detailed build internals, source-code
architecture, and history of which files came from where.

## Repository layout

```
.
├── src/                     v9.12 assembly + C source for DOS/32A and its utilities
├── bin/                     Vendored Borland TASM 5 + TLINK 7 + DPMI runtime
├── binw/                    2006 v9.1.2 reference binaries (preserved, untouched)
├── conf/dosbox.conf         DOSBox-X config used by the container build
├── docs/                    v8.0 Liberty Edition HTML user manual
│   └── historical/          Original 2002/2006 release READMEs, press release,
│                            author update log (preserved for posterity)
├── d32/                     Pre-built config-overlay profiles (.d32 files)
├── h32/  l32/  pctest/      Headers, libraries, and 2006 PCTEST.EXE binary
├── examples/                Sample ASM and C apps that bind DOS/32A
├── release/                 Generated release archive (gitignored)
├── Dockerfile               Container image definition
├── Makefile                 Host-side build orchestrator
├── make.bat                 In-container DOSBox-X build script
├── dosbox.sh                Container entrypoint (runs DOSBox-X headlessly)
├── CHANGELOG.md             Author's full changelog 2002-2006 + our v9.12.x maintenance entries
├── CLAUDE.md                Architecture and build internals (for Claude Code / human reference)
├── LICENSE                  Apache-style "Liberty Edition" license from Narech Koumar
├── README.md                This file
└── version.id               Current release tag
```

## Provenance

- **`src/`**: v9.1.2 source from the 2006 release archive, unzipped over the
  v8.00 Liberty Edition tree from
  [SourceForge](https://sourceforge.net/projects/dos32a/). Older v8.0-era docs
  (e.g. `docs/historical/press.txt`) are kept as-is.
- **`bin/`**: Borland TASM 5 + TLINK 7 + DPMI runtime, cherry-picked from
  [`yetmorecode/dos32a-ng`](https://github.com/yetmorecode/dos32a-ng) — see
  [`bin/NOTICE.md`](bin/NOTICE.md) for provenance and licensing context.
- **`src/dos32a/loader.asm`** (v9.12.2 VXD patch): cherry-picked from
  `dos32a-ng@bf28a94 + @24a75e8`, originally by leecher1337.

The `v9.12.1` and `v9.12.2` source changes are all my own (Tim Beck, 2026)
and are described in detail in [CHANGELOG.md](CHANGELOG.md).

## License

[Apache-style "Liberty Edition" license](LICENSE), authored by Narech Koumar
for the 2002 source release. Permits unrestricted redistribution and use,
including in commercial products, subject to:

1. Source redistributions retain the copyright notice.
2. Binary redistributions reproduce the notice in documentation or about-box.
3. End-user documentation acknowledges *"This product uses DOS/32 Advanced
   DOS Extender technology."*
4. Derived works may not be called "DOS/32A" or "DOS/32 Advanced".

Vendored Borland binaries under `bin/` have a separate licensing posture
documented in [`bin/NOTICE.md`](bin/NOTICE.md).
