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

FROM ubuntu:${UBUNTU_TAG}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        dosbox \
        xauth \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

CMD ["/app/dosbox.sh"]
