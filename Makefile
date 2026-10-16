.PHONY: all run fmt test image dist check clean

NOSTR_SECP256K1_LIB := build/linux/x64/release/libnostr_secp256k1.so
NOSTR_SECP256K1_SRCS := src/nostr_secp256k1.c src/nostr_secp256k1.h \
	linux/CMakeLists.txt \
	$(wildcard src/secp256k1/src/*.c src/secp256k1/src/*.h src/secp256k1/include/*.h)

DOCKER_IMAGE := sputnik-build
DOCKER_RUN := docker run --rm -v "$(CURDIR):/src:ro" \
	-e HOST_UID="$${SUDO_UID:-$$(id -u)}" -e HOST_GID="$${SUDO_GID:-$$(id -g)}"
WARN_DIRTY := test -z "$$(git status --porcelain)" || \
	echo "warning: only committed changes are used" >&2

all: fmt

run:
	flutter run --no-pub --release

test: $(NOSTR_SECP256K1_LIB)
	SPUTNIK_NOSTR_SECP256K1_LIBRARY="$(CURDIR)/$(NOSTR_SECP256K1_LIB)" flutter test

$(NOSTR_SECP256K1_LIB): $(NOSTR_SECP256K1_SRCS)
	flutter build linux --release
	touch $@

image:
	docker build -t $(DOCKER_IMAGE) -f contrib/Dockerfile contrib

dist: image
	@$(WARN_DIRTY)
	mkdir -p dist
	$(DOCKER_RUN) -v "$(CURDIR)/dist:/out" $(DOCKER_IMAGE) /src/contrib/docker_build.sh dist

check: image
	@$(WARN_DIRTY)
	$(DOCKER_RUN) $(DOCKER_IMAGE) /src/contrib/docker_build.sh check

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/*.sh
	yamlfmt .github/dependabot.yml .github/workflows/*.yml
	mbake format Makefile
	npx prettier --write docs/*.md README.md

clean:
	flutter clean