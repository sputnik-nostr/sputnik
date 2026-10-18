#!/usr/bin/env bash

# Tests android_sdk_package.sh with zips served from a directory: the layout
# it makes, and that it installs nothing whose hash is not the pinned one.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
package="$here/../android_sdk_package.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repository="$work/repository"
export ANDROID_HOME="$work/sdk"
export ANDROID_SDK_REPOSITORY="file://$repository"
mkdir -p "$repository" "$work/platform/android-9" "$work/bare"

# A platform with a directory of its own in the zip, and a package like CMake's
# whose files are at the root of the zip. Both have a tool and a symlink, as
# the NDK has.
cat >"$work/platform/android-9/source.properties" <<'EOF'
Pkg.Desc=Android SDK Platform 9
Pkg.Revision=1
AndroidVersion.ApiLevel=9
AndroidVersion.CodeName=
AndroidVersion.ExtensionLevel=2
AndroidVersion.IsBaseSdk=true
Layoutlib.Api=15
EOF
echo 'stubs' >"$work/platform/android-9/android.jar"
printf '#!/bin/sh\n' >"$work/platform/android-9/tool"
chmod +x "$work/platform/android-9/tool"
ln -s android.jar "$work/platform/android-9/link"
(cd "$work/platform" && zip -qry "$repository/platform-9_r01.zip" android-9)
echo 'Pkg.Revision = 3.22.1' >"$work/bare/source.properties"
(cd "$work/bare" && zip -qry "$repository/bare-9.zip" .)
platform_sha="$(sha256sum "$repository/platform-9_r01.zip" | cut -d' ' -f1)"
bare_sha="$(sha256sum "$repository/bare-9.zip" | cut -d' ' -f1)"

installs() {
    "$package" "$@" >/dev/null
}

check "installs a package into the directory it is given" \
    installs platform-9_r01.zip "$platform_sha" android-9 platforms/android-9
check "with its files" test -f "$ANDROID_HOME/platforms/android-9/android.jar"
check "with the modes and symlinks of the zip" \
    test -x "$ANDROID_HOME/platforms/android-9/tool" -a -L "$ANDROID_HOME/platforms/android-9/link"
# The Android Gradle plugin finds packages by their package.xml, which is not
# in the zip.
package_xml="$ANDROID_HOME/platforms/android-9/package.xml"
check "writes the package.xml of a platform" \
    grep -q 'path="platforms;android-9"' "$package_xml"
check "with its API level and extension" \
    grep -Eqz '<api-level>9</api-level>.*<extension-level>2</extension-level>.*<base-extension>true</base-extension>' "$package_xml"
check "and its revision" \
    grep -Eqz '<revision>\s*<major>1</major>\s*</revision>' "$package_xml"
check "installs a package whose files are at the root of the zip" \
    installs bare-9.zip "$bare_sha" . cmake/9
check "with its files at the destination" test -f "$ANDROID_HOME/cmake/9/source.properties"
package_xml="$ANDROID_HOME/cmake/9/package.xml"
check "writes the package.xml of another kind of package" \
    grep -q 'path="cmake;9".*obsolete="false"' "$package_xml"
check "with a revision of three parts" \
    grep -Eqz '<major>3</major>\s*<minor>22</minor>\s*<micro>1</micro>' "$package_xml"
check "and no platform details" grep -q 'genericDetailsType' "$package_xml"
check "and leaves nothing of its own in the SDK" \
    test -z "$(find "$ANDROID_HOME" -maxdepth 1 -name '.*')"

# The pin: the zip is what changes, the hash does not.
check_not "refuses a zip with another hash" \
    installs platform-9_r01.zip "$bare_sha" android-9 platforms/android-8 2>/dev/null
check "and installs nothing of it" test ! -e "$ANDROID_HOME/platforms/android-8"
check "or leaves its files behind" test -z "$(find "$ANDROID_HOME" -maxdepth 1 -name '.*')"
echo 'tampered' >"$work/platform/android-9/android.jar"
(cd "$work/platform" && zip -qry "$repository/platform-9_r01.zip" android-9)
check_not "refuses a zip that was replaced after it was pinned" \
    installs platform-9_r01.zip "$platform_sha" android-9 platforms/android-7 2>/dev/null
check "installing nothing" test ! -e "$ANDROID_HOME/platforms/android-7"

mkdir "$work/norevision"
echo 'files only' >"$work/norevision/readme"
(cd "$work/norevision" && zip -qry "$repository/norevision.zip" .)
check_not "refuses a package that does not say its revision" \
    installs norevision.zip "$(sha256sum "$repository/norevision.zip" | cut -d' ' -f1)" . cmake/5 2>/dev/null
check "and installs nothing of it" test ! -e "$ANDROID_HOME/cmake/5"

check_not "refuses to install over a package" \
    installs bare-9.zip "$bare_sha" . cmake/9 2>/dev/null
check "and leaves the package as it was" grep -q 'Pkg.Revision = 3.22.1' "$ANDROID_HOME/cmake/9/source.properties"
check_not "fails when the zip does not exist" \
    installs missing.zip "$bare_sha" . cmake/8 2>/dev/null
check_not "needs all four arguments" "$package" bare-9.zip "$bare_sha" . 2>/dev/null
check_not "takes a zip's name, not a path" \
    "$package" ../repository/bare-9.zip "$bare_sha" . cmake/6 2>/dev/null

finish
