.PHONY: all run fmt test dist clean

NOSTR_SECP256K1_LIB := build/linux/x64/release/libnostr_secp256k1.so
NOSTR_SECP256K1_SRCS := src/nostr_secp256k1.c src/nostr_secp256k1.h \
	linux/CMakeLists.txt \
	$(wildcard src/secp256k1/src/*.c src/secp256k1/src/*.h src/secp256k1/include/*.h)

DOCKER_IMAGE := sputnik-build

all: fmt

run:
	flutter run --no-pub --release

test: $(NOSTR_SECP256K1_LIB)
	SPUTNIK_NOSTR_SECP256K1_LIBRARY="$(CURDIR)/$(NOSTR_SECP256K1_LIB)" flutter test

$(NOSTR_SECP256K1_LIB): $(NOSTR_SECP256K1_SRCS)
	flutter build linux --release
	touch $@

dist:
	docker build -t $(DOCKER_IMAGE) -f contrib/Dockerfile contrib
	mkdir -p dist
	docker run --rm -v "$(CURDIR):/src:ro" -v "$(CURDIR)/dist:/out" \
		-e HOST_UID="$${SUDO_UID:-$$(id -u)}" -e HOST_GID="$${SUDO_GID:-$$(id -g)}" \
		$(DOCKER_IMAGE) /src/contrib/docker_build.sh

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/*.sh
	yamlfmt .github/dependabot.yml .github/workflows/*.yml
	mbake format Makefile
	npx prettier --write docs/*.md README.md

clean:
	flutter clean