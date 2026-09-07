.PHONY: all run fmt clean

all: fmt

run:
	flutter run --no-pub --release

fmt:
	dart format .
	clang-format -i src/nostr_secp256k1.c
	clang-format -i src/nostr_secp256k1.h
	shfmt -w -i 4 contrib/gen_launcher_icons.sh

clean:
	flutter clean