.PHONY: all run fmt test clean

NOSTR_SECP256K1_LIB := build/linux/x64/release/libnostr_secp256k1.so
NOSTR_SECP256K1_SRCS := src/nostr_secp256k1.c src/nostr_secp256k1.h \
	linux/CMakeLists.txt \
	$(wildcard src/secp256k1/src/*.c src/secp256k1/src/*.h src/secp256k1/include/*.h)

all: fmt

run:
	flutter run --no-pub --release

test: $(NOSTR_SECP256K1_LIB)
	SPUTNIK_NOSTR_SECP256K1_LIBRARY="$(CURDIR)/$(NOSTR_SECP256K1_LIB)" flutter test

$(NOSTR_SECP256K1_LIB): $(NOSTR_SECP256K1_SRCS)
	flutter build linux --release
	touch $@

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/*.sh
	yamlfmt .github/dependabot.yml .github/workflows/*.yml
	mbake format Makefile
	npx prettier --write docs/*.md README.md

clean:
	flutter clean