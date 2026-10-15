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

cp sputnik-x86_64.AppImage /out/
(cd /out && sha256sum sputnik-x86_64.AppImage >SHA256SUMS)
if [[ -n ${HOST_UID:-} ]]; then
    chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" /out
fi
cat /out/SHA256SUMS
