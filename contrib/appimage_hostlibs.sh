# shellcheck shell=bash
#
# Sourced by package_appimage.sh and check_appimage_libs.sh: which shared
# libraries the AppImage leaves to the machine it runs on. Anything else that
# the executable or a bundled library needs must be bundled.
#
# The base is the AppImage project's list of libraries to assume on every
# system, vendored unmodified as appimage_excludelist:
#   https://github.com/AppImage/pkg2appimage/blob/15a64c20dc23a0154622ba25829364323903b6b5/excludelist
#   sha256 50db0f894f34b169c47a5cbc0c17dbab61e9edebca5bc8269a1e6ac1bf4bdad9
# (still the file's content at master 19e30b2 of 2025-07-21). To update it,
# download the new file, run `make check`, and change the commit and hash above.
#
# The list does not cover everything that the machine has to provide, so
# is_host_lib adds two groups: the GTK stack that the application is built
# against, and the graphics, windowing and audio libraries that have to match
# the drivers and services of the machine. Everything else is bundled, even
# where the build container happens to have it: it has libjpeg.so.8, and
# Debian and Fedora do not, so the AppImage did not start there.

declare -A excluded_libs
while read -r soname _; do
    [[ -z $soname || $soname == '#'* ]] && continue
    excluded_libs[$soname]=1
done <"$(dirname "${BASH_SOURCE[0]}")/appimage_excludelist"

# True if the library is left to the machine the AppImage runs on.
is_host_lib() {
    [[ -n ${excluded_libs[$1]:-} ]] && return 0
    case "$1" in
    # The GTK 3 libraries that `pkg-config --libs gtk+-3.0` names (zlib and
    # HarfBuzz are on the list), and the libepoxy that Flutter's embedder and
    # media_kit_video link. The application is built against the host's GTK,
    # and a bundled copy of a part of it would shadow the rest.
    libgtk-3.so.* | libgdk-3.so.* | libgdk_pixbuf-2.0.so.* | libgio-2.0.so.* | \
        libglib-2.0.so.* | libgobject-2.0.so.* | libpango-1.0.so.* | \
        libpangocairo-1.0.so.* | libcairo.so.* | libcairo-gobject.so.* | \
        libatk-1.0.so.* | libepoxy.so.*)
        return 0
        ;;
    # Graphics, windowing, audio and device libraries that have to match the
    # drivers and services of the machine, beyond what the list names.
    libGL*.so.* | libEGL.so.* | libOpenGL.so.* | libvulkan.so.* | \
        libva.so.* | libva-*.so.* | libvdpau.so.* | libX*.so.* | \
        libxcb*.so.* | libxkbcommon*.so.* | libwayland-*.so.* | \
        libpulse*.so.* | libudev.so.* | libsystemd.so.*)
        return 0
        ;;
    esac
    return 1
}
