#!/bin/bash
set -e

# tlink writes the linked exe to ..\..\out\dos32a.exe (relative to src/dos32a/).
# Create out/ before launching DOSBox so the link step doesn't fail.
mkdir -p /app/out

SDL_VIDEODRIVER=dummy dosbox-x -silent -fastlaunch -nogui -nomenu -exit -conf ./conf/dosbox.conf
