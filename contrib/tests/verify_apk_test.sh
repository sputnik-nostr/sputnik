#!/usr/bin/env bash

# Tests verify_apk.sh with stand-ins for apksigner and keytool, which sign by
# adding an APK signing block to a zip.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
verify="$here/../verify_apk.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat >"$work/bin/keytool" <<'STUB'
#!/usr/bin/env bash
# Creates the keystore that apksigner would read.
while [[ $# -gt 0 ]]; do
    [[ $1 == -keystore ]] && echo key >"$2"
    shift
done
STUB
cat >"$work/bin/apksigner" <<'STUB'
#!/usr/bin/env bash
# sign [options] --out <out> <in>: writes <in> with a signing block between the
# entries and the central directory (and the signature scheme options ignored).
# verify --print-certs <apk>: succeeds if the APK has a signing block.
set -euo pipefail
le() { # value bytes: little-endian bytes
    local i
    for ((i = 0; i < $2; i++)); do
        printf '%b' "$(printf '\\x%02x' $((($1 >> (8 * i)) & 255)))"
    done
}
has_block() {
    local size directory
    size="$(stat -c %s "$1")"
    directory="$(od --endian=little -An -tu4 -j $((size - 6)) -N 4 "$1" | tr -d ' ')"
    [[ $(tail -c +$((directory - 15)) "$1" | head -c 16) == 'APK Sig Block 42' ]]
}
if [[ $1 == verify ]]; then
    has_block "${@: -1}" || { echo "DOES NOT VERIFY"; exit 1; }
    echo "Signer #1 certificate SHA-256 digest: 0123abcd"
    exit 0
fi
args=("$@")
input="${args[-1]}"
for i in "${!args[@]}"; do
    [[ ${args[i]} == --out ]] && output="${args[i + 1]}"
done
size="$(stat -c %s "$input")"
directory="$(od --endian=little -An -tu4 -j $((size - 6)) -N 4 "$input" | tr -d ' ')"
payload="signature of $(basename "$KEY_NAME")"
{
    le $((${#payload} + 24)) 8
    printf '%s' "$payload"
    le $((${#payload} + 24)) 8
    printf 'APK Sig Block 42'
} >"$output.block"
{
    head -c "$directory" "$input"
    cat "$output.block"
    tail -c +$((directory + 1)) "$input"
} >"$output"
block=$((${#payload} + 32))
printf '%b' "$(printf '\\x%02x' $(((directory + block) & 255)) \
    $((((directory + block) >> 8) & 255)) $((((directory + block) >> 16) & 255)) 0)" |
    dd of="$output" bs=1 seek=$((size + block - 22 + 16)) conv=notrunc status=none
rm "$output.block"
STUB
chmod +x "$work/bin/keytool" "$work/bin/apksigner"
export PATH="$work/bin:$PATH"
export KEY_NAME=release-key

# Two builds of the app, and the release's signature on the first.
mkdir "$work/app"
head -c 3000 /dev/urandom >"$work/app/classes.dex"
head -c 5000 /dev/urandom >"$work/app/libapp.so"
(cd "$work/app" && zip -q -0 -X "$work/build.apk" classes.dex libapp.so)
echo "different" >"$work/app/libapp.so"
(cd "$work/app" && zip -q -0 -X "$work/other.apk" classes.dex libapp.so)
apksigner sign --out "$work/release.apk" "$work/build.apk"

ok_run() {
    output="$("$verify" "$@" 2>&1)"
}
check "a signed APK is its unsigned build plus the signature" ok_run "$work/release.apk" "$work/build.apk"
check "and says whose signature" grep -q 'SHA-256 digest: 0123abcd' <<<"$output"
status=0
output="$("$verify" "$work/release.apk" "$work/other.apk" 2>&1)" || status=$?
check "an APK of other contents is not" test "$status" -eq 1
check "and says so" grep -q 'is not .*other.apk plus a signature' <<<"$output"
status=0
output="$("$verify" "$work/build.apk" "$work/build.apk" 2>&1)" || status=$?
check "an unsigned APK is not a signed one" test "$status" -eq 1

# The release signature is not made with the throwaway key, and its block can
# differ in size from the one that is made here.
KEY_NAME=a-much-longer-key-name apksigner sign --out "$work/long.apk" "$work/build.apk"
check "the two signing blocks differ in size" \
    test "$(stat -c %s "$work/long.apk")" -ne "$(stat -c %s "$work/release.apk")"
check "yet it is the same build" ok_run "$work/long.apk" "$work/build.apk"

"$verify" --strip "$work/long.apk" "$work/stripped.apk"
check "cutting the signing block out gives back the unsigned APK" \
    cmp -s "$work/stripped.apk" "$work/build.apk"
check "which is still a zip" unzip -tqq "$work/stripped.apk"

status=0
"$verify" 2>/dev/null || status=$?
check "needs both arguments" test "$status" -eq 2
mkdir "$work/empty"
status=0
PATH="$work/empty" "$BASH" "$verify" "$work/release.apk" "$work/build.apk" 2>/dev/null || status=$?
check "needs apksigner and keytool" test "$status" -eq 2

finish
