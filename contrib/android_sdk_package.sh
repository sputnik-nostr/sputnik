#!/usr/bin/env bash

# Installs one Android SDK package into $ANDROID_HOME from its zip, which is
# downloaded directly and checked against its sha256 before anything is
# unpacked. sdkmanager is not used because it takes the current revision of a
# package, or a moving installer, and checks neither against a pin.
#
# usage: android_sdk_package.sh <zip> <sha256> <directory in the zip, or . for
#        its root> <destination below $ANDROID_HOME>
# The zip's name is in the <url> of the package in
# https://dl.google.com/android/repository/repository2-3.xml. The destination
# is the layout that the Android Gradle plugin expects, as sdkmanager makes
# it: platforms/android-35, ndk/28.2.13676358, platform-tools and so on.
#
# The plugin finds a package by its package.xml, which sdkmanager writes after
# unpacking and which is not in the zip. It is written here from the zip's
# source.properties, without the license that sdkmanager records as accepted.

set -euo pipefail

if [[ $# -ne 4 || $1 == */* ]]; then
    echo "usage: $0 <zip> <sha256> <directory in the zip, or .> <destination below \$ANDROID_HOME>" >&2
    exit 2
fi
zip="$1"
sha256="$2"
inner="$3"
destination="${ANDROID_HOME:?}/$4"
# ANDROID_SDK_REPOSITORY only lets the tests serve their own zips.
repository="${ANDROID_SDK_REPOSITORY:-https://dl.google.com/android/repository}"

if [[ -e $destination ]]; then
    echo "error: $destination exists already" >&2
    exit 1
fi

# Unpacked next to the destination, so that moving it into place is a rename.
mkdir -p "$ANDROID_HOME"
work="$(mktemp -d "$ANDROID_HOME/.install.XXXXXX")"
trap 'rm -rf "${work:?}"' EXIT

curl -fsSL -o "$work/$zip" "$repository/$zip"
echo "$sha256  $work/$zip" | sha256sum -c --quiet -
unzip -q "$work/$zip" -d "$work/unpacked"
source="$work/unpacked"
[[ $inner == . ]] || source="$source/$inner"

# property <name>: its value in source.properties.
property() {
    sed -n "s/^${1//./\\.}[[:space:]]*=[[:space:]]*//p" "$source/source.properties" | head -n 1 | tr -d '\r'
}

id="${4//\//;}"
revision="$(property Pkg.Revision)"
if [[ -z $revision ]]; then
    echo "error: $zip has no revision in its source.properties" >&2
    exit 1
fi
IFS=. read -r major minor micro <<<"$revision"
{
    cat <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02" xmlns:ns5="http://schemas.android.com/repository/android/generic/02" xmlns:ns9="http://schemas.android.com/sdk/android/repo/repository2/03">
    <localPackage path="$id" obsolete="false">
EOF
    if [[ $4 == platforms/* ]]; then
        cat <<EOF
        <type-details xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="ns9:platformDetailsType">
            <api-level>$(property AndroidVersion.ApiLevel)</api-level>
            <codename>$(property AndroidVersion.CodeName)</codename>
            <extension-level>$(property AndroidVersion.ExtensionLevel)</extension-level>
            <base-extension>$(property AndroidVersion.IsBaseSdk)</base-extension>
            <layoutlib api="$(property Layoutlib.Api)"/>
        </type-details>
EOF
    else
        echo '        <type-details xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="ns5:genericDetailsType"/>'
    fi
    echo '        <revision>'
    echo "            <major>$major</major>"
    [[ -z $minor ]] || echo "            <minor>$minor</minor>"
    [[ -z $micro ]] || echo "            <micro>$micro</micro>"
    cat <<EOF
        </revision>
        <display-name>$id</display-name>
    </localPackage>
</ns2:repository>
EOF
} >"$source/package.xml"

mkdir -p "$(dirname "$destination")"
mv "$source" "$destination"
echo "$4 from $zip"
