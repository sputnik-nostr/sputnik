#!/usr/bin/env bash

# Checks that a signed APK is a build of the sources and nothing else: that it
# is the unsigned APK of your own `make dist`, plus a signature.
#
# Signing aligns the files of the APK again, so the signed APK is not your
# unsigned one with a block added. Both are brought to the same form instead:
# your unsigned APK is signed with a throwaway key, exactly as the release does
# it, and the signing block is cut out of that and of the signed APK. What is
# left has to be identical to the last byte. (apksigcopier does the same by
# copying the block over.) The signature itself is checked with apksigner, and
# the certificate is printed, to compare with the fingerprint the project
# publishes.
#
# usage: verify_apk.sh <signed.apk> <unsigned.apk>
#        verify_apk.sh --strip <signed.apk> <output.apk>   (only cuts the block)
# Needs apksigner and keytool. Use the ones of the build image (build-tools
# 36.0.0), as the release does, so that both APKs are signed by the same
# program. For example, in the checkout that holds both files:
#   docker run --rm -v "$PWD:/w:ro" sputnik-build /w/contrib/verify_apk.sh \
#       /w/dist/sputnik-arm64-v8a.apk /w/dist/sputnik-arm64-v8a-unsigned.apk

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

# strip_signing_block <apk> <output>: the APK without its signing block (the
# last thing before the central directory, ending with a magic string), with
# the central directory's offset in the end record moved back to match.
strip_signing_block() {
    local apk="$1" output="$2" size end_record directory block_size start
    size="$(stat -c %s "$apk")"
    # An APK with a signing block has no zip comment, so the end of central
    # directory record is its last 22 bytes.
    end_record=$((size - 22))
    [[ $(tail -c 22 "$apk" | head -c 4 | od -An -tx1 | tr -d ' \n') == 504b0506 ]] ||
        fail "$apk: no end of central directory record"
    directory="$(od --endian=little -An -tu4 -j $((end_record + 16)) -N 4 "$apk" | tr -d ' ')"
    [[ $(tail -c +$((directory - 15)) "$apk" | head -c 16) == 'APK Sig Block 42' ]] ||
        fail "$apk has no APK signing block (it is not signed with v2 or v3)"
    block_size="$(od --endian=little -An -tu8 -j $((directory - 24)) -N 8 "$apk" | tr -d ' ')"
    start=$((directory - block_size - 8))
    {
        head -c "$start" "$apk"
        tail -c +$((directory + 1)) "$apk"
    } >"$output"
    # The new offset of the central directory, as four little-endian bytes.
    printf '%b' "$(printf '\\x%02x' $((start & 255)) $(((start >> 8) & 255)) \
        $(((start >> 16) & 255)) $(((start >> 24) & 255)))" |
        dd of="$output" bs=1 seek=$((end_record - (directory - start) + 16)) conv=notrunc status=none
}

if [[ ${1:-} == --strip && $# -eq 3 ]]; then
    strip_signing_block "$2" "$3"
    exit 0
fi
if [[ $# -ne 2 ]]; then
    echo "usage: $0 <signed.apk> <unsigned.apk>" >&2
    exit 2
fi
signed="$1"
unsigned="$2"
for tool in apksigner keytool; do
    if ! command -v "$tool" >/dev/null; then
        echo "error: $tool is needed" >&2
        exit 2
    fi
done

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

certificates="$(apksigner verify --print-certs "$signed")"
echo "signature of $signed:"
grep '^Signer' <<<"$certificates" || true

keytool -genkeypair -keystore "$work/throwaway.jks" -storepass throwaway \
    -keypass throwaway -alias throwaway -keyalg RSA -keysize 2048 \
    -validity 1 -dname CN=throwaway 2>/dev/null
apksigner sign --ks "$work/throwaway.jks" --ks-pass pass:throwaway \
    --key-pass pass:throwaway --v1-signing-enabled false \
    --v4-signing-enabled false --out "$work/resigned.apk" "$unsigned"

strip_signing_block "$signed" "$work/signed.stripped"
strip_signing_block "$work/resigned.apk" "$work/resigned.stripped"
if ! cmp "$work/signed.stripped" "$work/resigned.stripped"; then
    fail "$signed is not $unsigned plus a signature"
fi
echo "ok: $signed is $unsigned plus the signature above"
