.PHONY: all fmt

all: fmt

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c
	clang-format -i src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/gen_launcher_icons.sh