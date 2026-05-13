#!/bin/bash
set -e

# tlink writes the linked exe to ..\..\out\dos32a.exe (relative to src/dos32a/).
# Create out/ before launching DOSBox so the link step doesn't fail.
mkdir -p /app/out

SDL_VIDEODRIVER=dummy dosbox make.bat -config=./conf/dosbox.conf -exit
