#!/usr/bin/env bash

# Tests that `make image`, `dist` and `check` build from the commit, with a
# stand-in for docker that records what it is given. The working tree has
# changes to the Dockerfile and the build script, and an untracked file.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/tmp"
export TMPDIR="$work/tmp"
export DOCKER_LOG="$work/docker.log"

cat >"$work/bin/docker" <<'STUB'
#!/usr/bin/env bash
# build: records the Dockerfile and the context. run: records the image, the
# command, and the file that the command is in, found through the mounts.
mounts=()
case $1 in
build)
    shift
    while [[ $# -gt 1 ]]; do
        case $1 in
        -f) dockerfile="$2" ;;
        esac
        shift
    done
    echo "build: $(tr '\n' ' ' <"$dockerfile")[context: $(ls -A "$1" | LC_ALL=C sort | tr '\n' ' ')]" >>"$DOCKER_LOG"
    ;;
run)
    shift
    while [[ $1 == -* ]]; do
        case $1 in
        -v) mounts+=("$2") ;;
        esac
        [[ $1 == --rm ]] && shift || shift 2
    done
    for mount in "${mounts[@]}"; do
        [[ $mount == "$PWD":/src:ro ]] && echo "run: sources $mount" >>"$DOCKER_LOG"
        container="${mount#*:}"
        container="${container%%:*}"
        if [[ $2 == "$container"/* ]]; then
            echo "run: $2 $3 [$(tr '\n' ' ' <"${mount%%:*}/${2#"$container"/}")]" >>"$DOCKER_LOG"
        fi
    done
    ;;
esac
STUB
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH"

repo="$work/repo"
git init -q "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.org
cp "$here/../../Makefile" "$repo/Makefile"
mkdir "$repo/contrib"
echo 'FROM committed-image' >"$repo/contrib/Dockerfile"
printf '#!/bin/sh\n# committed driver\n' >"$repo/contrib/docker_build.sh"
chmod +x "$repo/contrib/docker_build.sh"
git -C "$repo" add .
git -C "$repo" -c commit.gpgsign=false commit -q -m "a commit"
commit="$(git -C "$repo" rev-parse --short HEAD)"

# make <target>...: runs make in the repository, keeping the output.
run_make() {
    : >"$DOCKER_LOG"
    (cd "$repo" && make "$@" 2>&1)
}

output="$(run_make dist)"
check_not "a clean tree gives no warning" grep -q warning <<<"$output"
check "the image is built from the committed Dockerfile" grep -q '^build: FROM committed-image \[' "$DOCKER_LOG"
check "from a context of the committed files only" grep -q 'context: Dockerfile docker_build.sh \]$' "$DOCKER_LOG"
check "the sources are mounted for the clone" grep -q '^run: sources' "$DOCKER_LOG"
check "the build script is the committed one" \
    grep -q '^run: /contrib/docker_build.sh dist \[#!/bin/sh # committed driver \]$' "$DOCKER_LOG"

echo '# changed' >>"$repo/contrib/Dockerfile"
echo '# changed' >>"$repo/contrib/docker_build.sh"
echo 'untracked' >"$repo/contrib/untracked_file"
output="$(run_make dist)"
check "uncommitted changes are warned about, once, with the commit that is built" \
    test "$(grep -c "warning: uncommitted changes are not built, only commit $commit" <<<"$output")" -eq 1
check "the image is still built from the committed Dockerfile" grep -q '^build: FROM committed-image \[' "$DOCKER_LOG"
check "without the changed line" test -z "$(grep 'changed' "$DOCKER_LOG" || true)"
check "and without the untracked file" test -z "$(grep 'untracked_file' "$DOCKER_LOG" || true)"

output="$(run_make check)"
check "check runs the committed build script too" grep -q '^run: /contrib/docker_build.sh check ' "$DOCKER_LOG"
output="$(run_make -o image dist)"
check "with the image left alone, dist builds no image" test -z "$(grep '^build:' "$DOCKER_LOG" || true)"
check "and still runs the committed build script" grep -q '^run: /contrib/docker_build.sh dist ' "$DOCKER_LOG"
check "nothing is left in the temporary directory" test -z "$(ls -A "$work/tmp")"

finish
