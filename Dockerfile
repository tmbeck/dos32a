# Build environment for rebuilding DOS/32A from source on a modern host.
#
# Runs DOSBox headlessly to drive the original Borland TASM 5 + TLINK
# toolchain (vendored under bin/) against the unmodified .asm source. The
# DOS-side build is identical to running on a real DOS box; we just put a
# Linux container around DOSBox.
#
# Originally derived from yetmorecode/dos32a-ng@7d62307. Retargeted to
# Ubuntu 26.04 (per project preference).
#
# No --platform pin: ubuntu:26.04 ships dosbox 0.74-3 for both amd64 and
# arm64, and DOSBox emulates x86 internally regardless of host arch, so
# the build output is identical across host platforms. On Apple Silicon
# this runs natively without Rosetta.

ARG UBUNTU_TAG=26.04
# Pin OW v2 snapshot for reproducibility; bump deliberately when needed.
ARG OW_SNAPSHOT=Last-CI-build

FROM ubuntu:${UBUNTU_TAG}
ARG OW_SNAPSHOT

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dosbox-x \
        xauth \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Open Watcom v2 - DOS-hosted toolchain (wcl, wcl386, wlib, wlink, C headers).
# Required for building the companion utilities (SB, SC, SS, SD, STUB32A,
# PCTEST, SVER, BUILD); the core dos32a.exe only needs TASM+TLINK from bin/.
#
# OW v2 layout footnote: despite the name, binw/ holds the MS-DOS MZ-format
# host binaries (16-bit DOS, "Win" historically referred to Win 3.x's DOS
# compatibility). binp/ is OS/2 LX-hosted (would need an OS/2 emulator to
# run). We extract binw/ + h/ to keep the image small (~60MB of additions).
RUN mkdir -p /opt/watcom \
    && curl -fsSL --retry 3 \
        "https://github.com/open-watcom/open-watcom-v2/releases/download/${OW_SNAPSHOT}/ow-snapshot.tar.xz" \
        -o /tmp/ow.tar.xz \
    && tar -xJf /tmp/ow.tar.xz -C /opt/watcom --strip-components=1 \
         ./binw ./h ./lib286 ./lib386 \
    && rm /tmp/ow.tar.xz \
    && chmod -R a+rX /opt/watcom \
    && chmod -R a+w /opt/watcom/binw

RUN mkdir /app
WORKDIR /app

CMD ["/app/dosbox.sh"]
