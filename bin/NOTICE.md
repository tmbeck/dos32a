# bin/ — vendored Borland toolchain

This directory contains six Borland binaries used by the containerized
build to compile and link the dos32a source. They are **not** part of
the DOS/32A project itself — they're build inputs, vendored here so the
container build is reproducible without external downloads.

| File | Size | Role |
|---|---|---|
| `TASM32.EXE` | 184,320 B | Borland Turbo Assembler v5.x (32-bit DOS, assembles 16/32-bit asm to OMF .obj) |
| `TLINK.EXE` | 120,426 B | Borland Turbo Linker v7.x (DOS MZ executable linker) |
| `RTM.EXE` | 120,853 B | Borland 16-bit DPMI run-time required by TASM32/TLINK |
| `32RTM.EXE` | 152,108 B | Borland 32-bit DPMI run-time required by TASM32 in 32-bit mode |
| `DPMI16BI.OVL` | 50,576 B | 16-bit DPMI overlay used by RTM |
| `DPMI32VM.OVL` | 58,376 B | 32-bit DPMI overlay used by 32RTM |

## Provenance

These binaries were cherry-picked into this repository from
`https://github.com/yetmorecode/dos32a-ng` (commit `880be04`, "Added bin",
authored by yetmorecode <yetmorecode@posteo.net>, 2021-12-05). They have
been publicly distributed in that repository since 2021 and used in its
publicly-runnable CI builds.

The cherry-pick preserves authorship metadata; see `git log -- bin/` for
the audit trail.

## Licensing posture

Borland released TASM and the surrounding DOS development tools as part
of the **Borland Antique Software** / **Borland Museum** collection in
the early 2000s, where Borland indicated it would not pursue
non-commercial redistribution of these now-obsolete DOS tools. The
collection itself was taken offline by Borland's successors (Inprise →
Embarcadero), but the policy is widely understood across the DOS
preservation community: TASM 5.x is treated as freely redistributable
for non-commercial archival, modding, and reverse-engineering use,
and is routinely vendored into open-source DOS projects (e.g.
[`yetmorecode/dos32a-ng`](https://github.com/yetmorecode/dos32a-ng/tree/main/bin),
[`grepwood/dos32awe`](https://github.com/grepwood/dos32awe), and many
others on GitHub).

**That said:** these binaries are not under an OSI-approved license, and
Embarcadero has never published a formal license statement for the
Antique Software collection. If you intend to distribute a product that
includes these binaries (rather than using them as build-time inputs
that don't ship), seek legal review.

For our use case — checking them in so a containerized build can rebuild
the DOS/32A v9.12 source on a modern host — this matches established
practice in the DOS preservation ecosystem. The DOS/32A source itself
(everything under `src/`) is governed by the Apache-style Liberty
Edition license documented in `../license` and is not affected by the
Borland tools' status.

## Verification

SHA-256 sums of each binary as cherry-picked (captured 2026-05-12):

```
aae09a81515a1c19cf358c736a948d0f1ec170eac85943274910f12de3b2c376  bin/32RTM.EXE
10acd85af3767634450a793f2af1e057de888621cbfc578d35d3fa91abc09661  bin/RTM.EXE
ba50fe547863b96242d98cff54cdf95ab268a8682395afad172eedbfc46c5b26  bin/TASM32.EXE
83a390b7a5ff7f5bb2be10d766dc2951fe19c372236d042badc88d2f96eb916d  bin/TLINK.EXE
d7b0fe7a20b535f983767d472a520da3bf03018932a1f65625916d0cd6e96110  bin/DPMI16BI.OVL
3aa1382ae3151a2e3932aa1a1d868642e7555f200432be7e9b6521cf7dc975e4  bin/DPMI32VM.OVL
```

Any divergence indicates the binaries were modified post-import.
