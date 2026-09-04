.PHONY: all fmt

all: fmt

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c
	clang-format -i src/nostr_secp256k1.h