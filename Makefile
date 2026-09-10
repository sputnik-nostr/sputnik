.PHONY: all run fmt test clean

NOSTR_SECP256K1_LIB := build/linux/x64/release/libnostr_secp256k1.so

all: fmt

run:
	flutter run --no-pub --release

test: $(NOSTR_SECP256K1_LIB)
	SPUTNIK_NOSTR_SECP256K1_LIBRARY="$(CURDIR)/$(NOSTR_SECP256K1_LIB)" flutter test

$(NOSTR_SECP256K1_LIB):
	flutter build linux --release

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c
	clang-format -i src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/gen_launcher_icons.sh

clean:
	flutter clean