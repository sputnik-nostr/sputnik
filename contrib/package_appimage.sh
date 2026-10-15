#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app=sputnik
bundle=build/linux/x64/release/bundle
appdir=build/AppDir
appimagetool="${APPIMAGETOOL:-appimagetool}"
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"

# Commit time, so rebuilding the same commit gives the same image.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"

# Pinned, since appimagetool otherwise downloads an unverified moving one.
runtime_version=20251108
runtime_sha256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
runtime="build/appimage-runtime-$runtime_version"
if ! echo "$runtime_sha256  $runtime" | sha256sum -c --status - 2>/dev/null; then
    mkdir -p build
    curl -fsSL -o "$runtime.part" \
        "https://github.com/AppImage/type2-runtime/releases/download/$runtime_version/runtime-x86_64"
    echo "$runtime_sha256  $runtime.part" | sha256sum -c --quiet -
    mv "$runtime.part" "$runtime"
fi

rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
    "$appdir/usr/share/metainfo" "$appdir/usr/share/icons/hicolor/1024x1024/apps"
cp -r "$bundle"/* "$appdir/usr/bin/"
lib="$appdir/usr/bin/lib"

# The host's GTK stack must not be shadowed by older bundled copies.
declare -A host_provided
while read -r soname _; do
    host_provided[$soname]=1
done < <(ldd "$lib/libflutter_linux_gtk.so" 2>/dev/null)

is_host_lib() {
    [[ -n ${host_provided[$1]:-} ]] && return 0
    case "$1" in
    ld-linux* | libc.so.* | libm.so.* | libdl.so.* | libpthread.so.* | \
        librt.so.* | libresolv.so.* | libutil.so.* | libstdc++.so.* | \
        libgcc_s.so.* | libz.so.* | libGL* | libEGL.so.* | libOpenGL.so.* | \
        libdrm.so.* | libgbm.so.* | libglapi.so.* | libvulkan.so.* | \
        libva.so.* | libva-*.so.* | libvdpau.so.* | libX*.so.* | \
        libxcb*.so.* | libwayland-*.so.* | libasound.so.* | libpulse*.so.* | \
        libpipewire-*.so.* | libjack.so.* | libudev.so.* | libsystemd.so.*)
        return 0
        ;;
    esac
    return 1
}

while read -r soname _ path _; do
    [[ $path == /* ]] || continue
    soname="${soname##*/}"
    [[ -e $lib/$soname ]] && continue
    is_host_lib "$soname" && continue
    cp -L "$path" "$lib/$soname"
    chmod u+w "$lib/$soname"
    patchelf --set-rpath '$ORIGIN' "$lib/$soname"
done < <(ldd "$appdir/usr/bin/$app" "$lib"/*.so 2>/dev/null | grep '=>' | sort -u)

# Flutter leaves the build machine's ephemeral dir as the plugins' RUNPATH.
for plugin in "$lib"/lib*_plugin.so; do
    patchelf --set-rpath '$ORIGIN' "$plugin"
done

mpv_libs=("$lib"/libmpv.so.*)
if [[ ! -e ${mpv_libs[0]} ]]; then
    echo "error: no libmpv.so.* was bundled; is libmpv installed on this machine?" >&2
    exit 1
fi
mpv_lib="${mpv_libs[0]##*/}"

cp assets/icon/icon.png "$appdir/usr/share/icons/hicolor/1024x1024/apps/$app.png"
ln -s "usr/share/icons/hicolor/1024x1024/apps/$app.png" "$appdir/$app.png"

cat >"$appdir/usr/share/applications/$app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sputnik
Comment=A minimal Nostr client
Exec=$app
Icon=$app
Terminal=false
Categories=Network;
X-AppImage-Version=$version
EOF
ln -s "usr/share/applications/$app.desktop" "$appdir/$app.desktop"

cat >"$appdir/usr/share/metainfo/$app.appdata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$app</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <name>Sputnik</name>
  <summary>A minimal, cross-platform Nostr client</summary>
  <description>
    <p>
      Sputnik is a minimal Nostr client focused on privacy, security and
      performance.
    </p>
  </description>
  <launchable type="desktop-id">$app.desktop</launchable>
  <url type="homepage">https://github.com/sputnik-nostr/sputnik</url>
  <url type="bugtracker">https://github.com/sputnik-nostr/sputnik/issues</url>
  <content_rating type="oars-1.1">
    <content_attribute id="social-chat">intense</content_attribute>
  </content_rating>
</component>
EOF

# media_kit dlopens libmpv by name, which could pick up a different host copy.
cat >"$appdir/AppRun" <<EOF
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
export LIBMPV_LIBRARY_PATH="\$HERE/usr/bin/lib/$mpv_lib"
exec "\$HERE/usr/bin/$app" "\$@"
EOF
chmod +x "$appdir/AppRun"

# The build time must not show in the image.
find "$appdir" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

# The AppStream ID is not reverse-DNS yet, which appstreamcli rejects.
ARCH=x86_64 "$appimagetool" --appimage-extract-and-run --no-appstream \
    --runtime-file "$runtime" "$appdir" "$app-x86_64.AppImage"
