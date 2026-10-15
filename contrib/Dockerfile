# Release build environment; every input is pinned so builds are reproducible.
FROM ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401

ARG UBUNTU_SNAPSHOT=20261001T000000Z
ARG FLUTTER_VERSION=3.47.7
ARG FLUTTER_COMMIT=abaf9c523780a608bd46686fd5e53740a07077f8
ARG APPIMAGETOOL_VERSION=1.9.1
ARG APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=UTC \
    CC=clang \
    CXX=clang++ \
    PATH=/opt/flutter/bin:$PATH

# No CA bundle yet for the first install; apt still checks signed metadata.
RUN sed -i \
    -e "s|http://archive.ubuntu.com/ubuntu/|https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/|" \
    -e "s|http://security.ubuntu.com/ubuntu/|https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/|" \
    /etc/apt/sources.list \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && apt-get -o Acquire::https::Verify-Peer=false install -y \
    --no-install-recommends ca-certificates \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    clang cmake curl file git libgtk-3-dev liblzma-dev \
    libmpv-dev libsecret-1-dev libstdc++-12-dev make ninja-build patchelf \
    pkg-config unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git /opt/flutter \
    && test "$(git -C /opt/flutter rev-parse HEAD)" = "$FLUTTER_COMMIT" \
    && flutter --disable-analytics \
    && dart --disable-analytics \
    && flutter precache --linux --no-android --no-ios --no-web \
    --no-macos --no-windows --no-fuchsia

RUN curl -fsSL -o /usr/local/bin/appimagetool \
    "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage" \
    && echo "${APPIMAGETOOL_SHA256}  /usr/local/bin/appimagetool" | sha256sum -c - \
    && chmod +x /usr/local/bin/appimagetool
