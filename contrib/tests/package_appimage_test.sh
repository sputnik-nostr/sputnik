#!/usr/bin/env bash

# Tests which libraries package_appimage.sh bundles, on a fake release bundle
# whose libraries mirror the real ones: the GTK stack that the engine links
# needs libjpeg.so.8 (as gdk-pixbuf does on the build container), and so does
# libmpv, which the engine does not link.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
# shellcheck source=elf.sh
source "$here/elf.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
elf_init "$work"

# Libraries of the build machine, found through LD_LIBRARY_PATH.
sys="$work/sys"
mkdir "$sys"
elf_lib "$sys/libgdk_pixbuf-2.0.so.0" libgdk_pixbuf-2.0.so.0 '' libjpeg.so.8 libtiff-only.so.1
elf_lib "$sys/libjpeg.so.8" libjpeg.so.8 ''
elf_lib "$sys/libtiff-only.so.1" libtiff-only.so.1 ''
elf_lib "$sys/libpulse.so.0" libpulse.so.0 '' libpulsecommon-99.so
elf_lib "$sys/libpulsecommon-99.so" libpulsecommon-99.so ''
elf_lib "$sys/libmpv.so.1" libmpv.so.1 '' libjpeg.so.8 libass-fake.so.9 libpulse.so.0
elf_lib "$sys/libass-fake.so.9" libass-fake.so.9 ''
elf_lib "$sys/libvanished.so.3" libvanished.so.3 ''

# A copy of the repository's packaging scripts around a release bundle.
# new_repo <name> [needed...]: libmpv needs the libraries as well.
new_repo() {
    local repo="$work/$1" bundle
    shift
    bundle="$repo/build/linux/x64/release/bundle"
    mkdir -p "$repo/contrib" "$repo/assets/icon" "$bundle/lib" "$bundle/data"
    cp "$here"/../package_appimage.sh "$here"/../check_appimage_libs.sh \
        "$here"/../appimage_hostlibs.sh "$here"/../appimage_excludelist "$repo/contrib/"
    echo 'version: 0.1.0+1' >"$repo/pubspec.yaml"
    touch "$repo/assets/icon/icon_round.png"
    elf_exe "$bundle/sputnik" '$ORIGIN/lib' libmedia_kit_video_plugin.so libflutter_linux_gtk.so
    elf_lib "$bundle/lib/libflutter_linux_gtk.so" libflutter_linux_gtk.so '$ORIGIN' libgdk_pixbuf-2.0.so.0
    elf_lib "$bundle/lib/libmedia_kit_video_plugin.so" libmedia_kit_video_plugin.so \
        /build/tree/plugins libflutter_linux_gtk.so libmpv.so.1 "$@"
    cp "$work/lib.so" "$bundle/lib/libapp.so"
    echo "$repo"
}

# package <repo>: runs the packaging as far as the AppDir.
package() {
    (cd "$1" && SOURCE_DATE_EPOCH=1 LD_LIBRARY_PATH="$sys" contrib/package_appimage.sh --appdir-only)
}

# bundled <repo>: the names in the AppDir's lib/, in one line.
bundled() {
    local file
    for file in "$1"/build/AppDir/usr/bin/lib/*; do
        echo "${file##*/}"
    done | LC_ALL=C sort | tr '\n' ' '
}

repo="$(new_repo ok)"
status=0
package "$repo" >"$work/ok.log" 2>&1 || status=$?
check "packages a bundle whose libraries the container has" test "$status" -eq 0
check "bundles what the bundle needs, including libjpeg.so.8" \
    test "$(bundled "$repo")" = "libapp.so libass-fake.so.9 libflutter_linux_gtk.so libjpeg.so.8 libmedia_kit_video_plugin.so libmpv.so.1 "
check "leaves the GTK stack to the host, with what only it needs" \
    test ! -e "$repo/build/AppDir/usr/bin/lib/libgdk_pixbuf-2.0.so.0" -a ! -e "$repo/build/AppDir/usr/bin/lib/libtiff-only.so.1"
check "leaves a host library's own dependencies to the host" \
    test ! -e "$repo/build/AppDir/usr/bin/lib/libpulsecommon-99.so"
check "the bundled copies search their own directory" \
    test "$(patchelf --print-rpath "$repo/build/AppDir/usr/bin/lib/libjpeg.so.8")" = '$ORIGIN'
check "the plugin does not search the build tree" \
    test "$(patchelf --print-rpath "$repo/build/AppDir/usr/bin/lib/libmedia_kit_video_plugin.so")" = '$ORIGIN'
check "the check ran, and listed the libraries left to the host" \
    grep -q '^  libgdk_pixbuf-2.0.so.0$' "$work/ok.log"
check "the AppRun names the bundled libmpv" \
    grep -q 'LIBMPV_LIBRARY_PATH="$HERE/usr/bin/lib/libmpv.so.1"' "$repo/build/AppDir/AppRun"

repo="$(new_repo missing libnowhere.so.7)"
status=0
package "$repo" >"$work/missing.log" 2>&1 || status=$?
check "stops when a library cannot be found" test "$status" -eq 1
check "and says which" grep -q 'libmedia_kit_video_plugin.so needs libnowhere.so.7, which the loader cannot find' "$work/missing.log"

finish
