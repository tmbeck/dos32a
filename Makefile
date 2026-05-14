# Host-side build orchestration for DOS/32A.
#
# The actual build runs inside a Linux container under DOSBox, driving the
# vendored Borland TASM 5 + TLINK toolchain (bin/) against the original 2006
# .asm source. This Makefile is a thin wrapper for the host -- everything
# interesting happens in dosbox.sh / conf/dosbox.conf / src/dos32a/make.bat.
#
# Output: out/dos32a.exe (drop-in replacement for the 2006 binw/dos32a.exe).

DOCKER_IMAGE    ?= dos32a-build:latest
OUT             ?= out

EXE := $(OUT)/dos32a.exe
REF := binw/dos32a.exe

.PHONY: all image build shell run clean

all: build

image:
	docker build -t $(DOCKER_IMAGE) .

build: $(EXE)

$(EXE):
	@mkdir -p $(OUT)
	docker run --rm \
	    -v $(CURDIR):/app \
	    $(DOCKER_IMAGE)
	@echo
	@echo "Rebuilt: $(EXE) ($$(stat -f '%z' $(EXE)) bytes)"
	@echo "2006 ref: $(REF) ($$(stat -f '%z' $(REF)) bytes)"

# Drop into a bash shell in the build container. Useful for poking at
# DOSBox config or running tasm32/tlink manually.
shell:
	docker run --rm -it \
	    -v $(CURDIR):/app \
	    --entrypoint /bin/bash \
	    $(DOCKER_IMAGE)

# Run the rebuilt dos32a.exe in dosbox-x on the host (smoke test).
# Requires `brew install dosbox-x` on macOS.
run: $(EXE)
	dosbox-x $(EXE)

clean:
	rm -rf $(OUT)
	@# Case-insensitive on macOS APFS: DOS tools emit UPPERCASE .OBJ / .LST etc.
	find src \( -iname '*.obj' -o -iname '*.lst' -o -iname '*.map' \
	         -o -iname '*.exe' -o -iname '*.err' -o -iname '*.lib' \) -delete
	@# Note: -iname required because DOSBox-X writes uppercase filenames
	@# into mounted host dirs (BUILD.LOG, not build.log).
	@find . -maxdepth 1 \( -iname 'build.log' -o -iname 'probe.log' \
	                       -o -iname 't.c' -o -iname 't.exe' \
	                       -o -iname 't32.c' -o -iname 't32.exe' \) -delete
