#!/usr/bin/env bash

# Runs every test in this directory; the build scripts in contrib/ have no
# other tests. Needs a C compiler, patchelf and the tools the scripts use.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for test in "$here"/*_test.sh; do
    echo "# ${test##*/}"
    "$test" || failed=1
done
exit "$failed"
