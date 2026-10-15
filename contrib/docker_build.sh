#!/usr/bin/env bash

# Runs in contrib/Dockerfile: builds /src's HEAD at a fixed path into /out.

set -euo pipefail

git config --global --add safe.directory '*'
git clone --quiet /src /build/sputnik
cd /build/sputnik
# The submodule comes from the local checkout, not the network.
git config submodule.src/secp256k1.url /src/.git/modules/src/secp256k1
git -c protocol.file.allow=always submodule update --init --quiet

flutter pub get
flutter build linux --release
contrib/package_appimage.sh
SPUTNIK_UNSIGNED=1 flutter build apk --release --split-per-abi

cp sputnik-x86_64.AppImage /out/
for abi in armeabi-v7a arm64-v8a x86_64; do
    cp "build/app/outputs/flutter-apk/app-$abi-release.apk" \
        "/out/sputnik-$abi-unsigned.apk"
done
(cd /out && sha256sum sputnik-x86_64.AppImage sputnik-*-unsigned.apk >SHA256SUMS)
if [[ -n ${HOST_UID:-} ]]; then
    chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" /out
fi
cat /out/SHA256SUMS
