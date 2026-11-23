#!/usr/bin/env bash

# Tests check_appimage_libs.sh on AppDirs built from tiny ELF files.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
# shellcheck source=elf.sh
source "$here/elf.sh"
check_libs="$here/../check_appimage_libs.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
elf_init "$work"

# new_appdir <name> [needed...]: an AppDir whose executable needs the libraries
# and finds the bundled ones in usr/bin/lib. Prints its path.
new_appdir() {
    local dir="$work/$1"
    shift
    mkdir -p "$dir/usr/bin/lib"
    elf_exe "$dir/usr/bin/sputnik" '$ORIGIN/lib' "$@"
    echo "$dir"
}

# run <AppDir>: runs the check, keeping its output and exit status.
run() {
    status=0
    output="$("$check_libs" "$1" 2>&1)" || status=$?
}

passes() {
    run "$1"
    [[ $status -eq 0 ]] || echo "$output" >&2
    [[ $status -eq 0 ]]
}

rejects() {
    run "$1"
    [[ $status -eq 1 && $output == *"$2"* ]] || echo "status $status: $output" >&2
    [[ $status -eq 1 && $output == *"$2"* ]]
}

dir="$(new_appdir bundled libfoo.so.1 libgtk-3.so.0 libGL.so.1)"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '$ORIGIN' libX11.so.6 libva.so.2
check "a bundled library and the host libraries are accepted" passes "$dir"
check "the host libraries are listed" grep -q '^  libgtk-3.so.0$' <<<"$output"
check "a bundled library is not listed as left to the host" \
    bash -c '! grep -q "libfoo" <<<"$1"' _ "$output"

# The failure this test is named for: a library that the build machine has
# and others do not.
dir="$(new_appdir jpeg libfoo.so.1)"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '$ORIGIN' libjpeg.so.8
check "a library that is neither bundled nor on the host list is rejected" \
    rejects "$dir" "libfoo.so.1 needs libjpeg.so.8"
elf_lib "$dir/usr/bin/lib/libjpeg.so.8" libjpeg.so.8 '$ORIGIN'
check "the same library bundled is accepted" passes "$dir"

dir="$(new_appdir png libpng16.so.16)"
check "a compression or image library is bundled, not assumed" \
    rejects "$dir" "sputnik needs libpng16.so.16"

dir="$(new_appdir hostfamilies libGLESv2.so.2 libvulkan.so.1 libva-drm.so.2 libvdpau.so.1 \
    libXrandr.so.2 libxcb-shm.so.0 libxkbcommon.so.0 libwayland-egl.so.1 \
    libpulse.so.0 libudev.so.1 libsystemd.so.0 libasound.so.2)"
check "the graphics, windowing and audio families are left to the host" passes "$dir"

dir="$(new_appdir buildpath libfoo.so.1)"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '/home/builder/build/plugins'
check "a RUNPATH into the build machine is rejected" \
    rejects "$dir" "libfoo.so.1: RUNPATH entry /home/builder/build/plugins"

dir="$(new_appdir norunpath libfoo.so.1)"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '$ORIGIN' libbar.so.2
elf_lib "$dir/usr/bin/lib/libbar.so.2" libbar.so.2 ''
check "passes when the RUNPATH leads to the dependencies" passes "$dir"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '' libbar.so.2
check "a bundled dependency that the RUNPATH does not lead to is rejected" \
    rejects "$dir" "libbar.so.2 is bundled, but the RUNPATH of lib/libfoo.so.1"

dir="$(new_appdir exerunpath libfoo.so.1)"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '$ORIGIN'
elf_exe "$dir/usr/bin/sputnik" '' libfoo.so.1
check "an executable that does not search lib/ is rejected" \
    rejects "$dir" "libfoo.so.1 is bundled, but the RUNPATH of sputnik"

# What the loader says about the files, which a reading of the headers cannot.
dir="$(new_appdir damaged libfoo.so.1)"
echo "not a library" >"$dir/usr/bin/lib/libfoo.so.1"
check "a bundled file the loader cannot use is rejected" rejects "$dir" "ldd failed"

# Every bundled library goes through the loader, not only what the executable
# reaches: nothing needs this one, and the headers say nothing against it.
dir="$(new_appdir unneeded)"
printf '\177ELF truncated' >"$dir/usr/bin/lib/libunused.so.1"
check "a broken library that nothing needs is rejected as well" \
    rejects "$dir" "ldd failed on lib/libunused.so.1"

# The loader skips a library built for another architecture, so what the
# executable needs is not found, though the headers look right.
dir="$(new_appdir wrongarch libfoo.so.1)"
elf_lib "$dir/usr/bin/lib/libfoo.so.1" libfoo.so.1 '$ORIGIN'
printf '\050\000' | dd of="$dir/usr/bin/lib/libfoo.so.1" bs=1 seek=18 conv=notrunc status=none
check "a library for another architecture is rejected" \
    rejects "$dir" "the loader cannot find libfoo.so.1 for sputnik"

dir="$work/empty"
mkdir -p "$dir"
check_not "an AppDir without an executable is a usage error" "$check_libs" "$dir" 2>/dev/null
check_not "no argument is a usage error" "$check_libs" 2>/dev/null

finish
