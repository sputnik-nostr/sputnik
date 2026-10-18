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

finish
