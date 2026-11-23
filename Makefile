.PHONY: all run fmt test warn-uncommitted image dist check clean

NOSTR_SECP256K1_LIB := build/linux/x64/release/libnostr_secp256k1.so
NOSTR_SECP256K1_SRCS := src/nostr_secp256k1.c src/nostr_secp256k1.h \
	linux/CMakeLists.txt \
	$(wildcard src/secp256k1/src/*.c src/secp256k1/src/*.h src/secp256k1/include/*.h)

DOCKER_IMAGE := sputnik-build
DOCKER_RUN := docker run --rm -v "$(CURDIR):/src:ro" \
	-e HOST_UID="$${SUDO_UID:-$$(id -u)}" -e HOST_GID="$${SUDO_GID:-$$(id -g)}"
# The image and the build script are cut out of the commit, like the sources
# that the container clones from it, so what is built is what the commit says.
# For the rest of the command, $$tmp holds contrib/ as committed.
HEAD_CONTRIB := tmp="$$(mktemp -d)" && trap 'rm -rf "$$tmp"' EXIT && \
	chmod 755 "$$tmp" && git archive HEAD contrib | tar -x -C "$$tmp" &&

all: fmt

run:
	flutter run --no-pub --release

test: $(NOSTR_SECP256K1_LIB)
	SPUTNIK_NOSTR_SECP256K1_LIBRARY="$(CURDIR)/$(NOSTR_SECP256K1_LIB)" flutter test

$(NOSTR_SECP256K1_LIB): $(NOSTR_SECP256K1_SRCS)
	flutter build linux --release
	touch $@

warn-uncommitted:
	@test -z "$$(git status --porcelain)" || \
		echo "warning: uncommitted changes are not built, only commit $$(git rev-parse --short HEAD)" >&2

image: warn-uncommitted
	$(HEAD_CONTRIB) docker build -t $(DOCKER_IMAGE) -f "$$tmp/contrib/Dockerfile" "$$tmp/contrib"

dist: warn-uncommitted image
	mkdir -p dist
	$(HEAD_CONTRIB) $(DOCKER_RUN) -v "$(CURDIR)/dist:/out" -v "$$tmp/contrib:/contrib:ro" \
		$(DOCKER_IMAGE) /contrib/docker_build.sh dist

check: warn-uncommitted image
	$(HEAD_CONTRIB) $(DOCKER_RUN) -v "$$tmp/contrib:/contrib:ro" \
		$(DOCKER_IMAGE) /contrib/docker_build.sh check

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/*.sh contrib/tests/*.sh
	yamlfmt .github/dependabot.yml .github/workflows/*.yml
	mbake format Makefile
	npx prettier --write docs/*.md README.md

clean:
	flutter clean