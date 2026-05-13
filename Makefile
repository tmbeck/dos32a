# Host-side build orchestration for DOS/32A.
#
# The actual build runs inside a Linux container under DOSBox, driving the
# vendored Borland TASM 5 + TLINK toolchain (bin/) against the original 2006
# .asm source. This Makefile is a thin wrapper for the host -- everything
# interesting happens in dosbox.sh / conf/dosbox.conf / src/dos32a/make.bat.
#
# Output: out/dos32a.exe (drop-in replacement for the 2006 binw/dos32a.exe).

DOCKER_IMAGE    ?= dos32a-build:latest
DOCKER_PLATFORM ?= linux/amd64
OUT             ?= out

EXE := $(OUT)/dos32a.exe
REF := binw/dos32a.exe

.PHONY: all image build shell run clean

all: build

image:
	docker build --platform=$(DOCKER_PLATFORM) -t $(DOCKER_IMAGE) .

build: $(EXE)

$(EXE):
	@mkdir -p $(OUT)
	docker run --rm \
	    --platform=$(DOCKER_PLATFORM) \
	    -v $(CURDIR):/app \
	    $(DOCKER_IMAGE)
	@echo
	@echo "Rebuilt: $(EXE) ($$(stat -f '%z' $(EXE)) bytes)"
	@echo "2006 ref: $(REF) ($$(stat -f '%z' $(REF)) bytes)"

# Drop into a bash shell in the build container. Useful for poking at
# DOSBox config or running tasm32/tlink manually.
shell:
	docker run --rm -it \
	    --platform=$(DOCKER_PLATFORM) \
	    -v $(CURDIR):/app \
	    --entrypoint /bin/bash \
	    $(DOCKER_IMAGE)

# Run the rebuilt dos32a.exe in dosbox-x on the host (smoke test).
# Requires `brew install dosbox-x` on macOS.
run: $(EXE)
	dosbox-x $(EXE)

clean:
	rm -rf $(OUT)
	find src -name '*.obj' -delete
	find src -name '*.lst' -delete
	find src -name '*.map' -delete
	find src -name '*.exe' -delete
