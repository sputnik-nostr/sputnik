#!/usr/bin/env bash

# Checks properties of the workflows that nothing else would notice.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
workflows="${WORKFLOWS:-$here/../../.github/workflows}"

# The BuildKit daemon runs every step of the image that signs the release.
for workflow in "$workflows"/*.yml; do
    if grep -q 'docker/setup-buildx-action@' "$workflow"; then
        check "${workflow##*/} pins the BuildKit image by digest" \
            grep -Eq '^\s+driver-opts: image=moby/buildkit:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' "$workflow"
    fi
done
check "the same BuildKit image in every workflow" \
    test "$(grep -h 'driver-opts:' "$workflows"/*.yml | sort -u | wc -l)" -eq 1

# The installable files are listed by name: a glob would also take the
# unsigned APKs, which the release does not ship.
check_not "the signed checksums are not made with a glob that takes unsigned APKs" \
    grep -Eq 'sha256sum .*sputnik-\*\.apk' "$workflows/build.yml"
check "the unsigned checksums go with the unsigned APKs" \
    grep -q 'dist/SHA256SUMS.unsigned' "$workflows/build.yml"

finish
