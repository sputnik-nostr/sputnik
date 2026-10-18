#!/usr/bin/env bash

# Checks that an AppDir does not depend on the machine it was built on: every
# shared library that the executable and the bundled libraries need is either
# bundled, and found through the file's RUNPATH, or left to the host on purpose
# (appimage_hostlibs.sh). The build container has far more libraries than a
# user's machine, so the loader finding a library here proves nothing; this
# resolves against the bundle and that list only.
#
# usage: check_appimage_libs.sh <AppDir>
# Prints the libraries that are left to the host. Exit status 1 if the AppDir
# needs anything else.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=appimage_hostlibs.sh
source "$here/appimage_hostlibs.sh"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <AppDir>" >&2
    exit 2
fi
app=sputnik
bin="$1/usr/bin"
lib="$bin/lib"
if [[ ! -x $bin/$app || ! -d $lib ]]; then
    echo "error: $1 has no usr/bin/$app and usr/bin/lib" >&2
    exit 2
fi
if ! command -v patchelf >/dev/null; then
    echo "error: patchelf is needed to read the dynamic section" >&2
    exit 2
fi

status=0
problem() {
    echo "error: $*" >&2
    status=1
}

is_elf() {
    [[ $(head -c 4 "$1") == $'\177ELF' ]]
}

files=("$bin/$app")
for file in "$lib"/*; do
    if [[ -f $file ]] && is_elf "$file"; then
        files+=("$file")
    fi
done

declare -A host_needed
for file in "${files[@]}"; do
    name="${file#"$bin"/}"
    dir="$(dirname "$file")"
    IFS=: read -ra runpath <<<"$(patchelf --print-rpath "$file")"
    for i in "${!runpath[@]}"; do
        if [[ ${runpath[i]} != "\$ORIGIN"* && ${runpath[i]} != "\${ORIGIN}"* ]]; then
            problem "$name: RUNPATH entry ${runpath[i]} is not relative to the file"
        fi
        runpath[i]="${runpath[i]//\$ORIGIN/$dir}"
        runpath[i]="${runpath[i]//\$\{ORIGIN\}/$dir}"
    done
    while read -r needed; do
        [[ -n $needed ]] || continue
        if [[ -e $lib/$needed ]]; then
            found=
            for entry in "${runpath[@]}"; do
                [[ -e $entry/$needed ]] && found=1
            done
            [[ -n $found ]] || problem "$name: $needed is bundled, but the RUNPATH of $name does not lead to it"
        elif is_host_lib "$needed"; then
            host_needed[$needed]=1
        else
            problem "$name needs $needed, which is neither bundled nor left to the host"
        fi
    done < <(patchelf --print-needed "$file")
done

# The same through the real loader, for the executable and for every bundled
# library, with an empty environment: whatever it cannot find has to be a host
# library. This also catches a file that nothing needs but that is broken.
for file in "${files[@]}"; do
    name="${file#"$bin"/}"
    if ! trace="$(env -i PATH=/usr/bin:/bin ldd "$file" 2>&1)"; then
        problem "ldd failed on $name: $trace"
        continue
    fi
    while read -r soname arrow result _; do
        if [[ $arrow == '=>' && $result == not ]] && ! is_host_lib "$soname"; then
            problem "the loader cannot find $soname for $name"
        fi
    done <<<"$trace"
done

echo "${#files[@]} files checked; ${#host_needed[@]} libraries are left to the host:"
if ((${#host_needed[@]} > 0)); then
    printf '  %s\n' "${!host_needed[@]}" | LC_ALL=C sort
fi
exit "$status"
