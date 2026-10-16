# Release build environment; every input is pinned so builds are reproducible.
FROM ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401

ARG UBUNTU_SNAPSHOT=20261001T000000Z
ARG FLUTTER_VERSION=3.47.7
ARG FLUTTER_COMMIT=abaf9c523780a608bd46686fd5e53740a07077f8
ARG APPIMAGETOOL_VERSION=1.9.1
ARG APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
ARG ANDROID_CMDLINE_TOOLS_BUILD=16111833
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=UTC \
    CC=clang \
    CXX=clang++ \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:$PATH

# No CA bundle yet for the first install; apt still checks signed metadata.
RUN sed -i \
    -e "s|http://archive.ubuntu.com/ubuntu/|https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/|" \
    -e "s|http://security.ubuntu.com/ubuntu/|https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/|" \
    /etc/apt/sources.list \
    && ! grep -rqsE "(archive|security)\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && apt-get -o Acquire::https::Verify-Peer=false install -y \
    --no-install-recommends ca-certificates \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    clang cmake curl file git libgtk-3-dev liblzma-dev \
    libmpv-dev libsecret-1-dev libstdc++-12-dev make ninja-build patchelf \
    openjdk-21-jdk-headless pkg-config unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

ARG ANDROID_BUILD_TOOLS=36.0.0
RUN curl -fsSL -o /tmp/cmdline-tools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_BUILD}_latest.zip" \
    && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install "platforms;android-37" \
    "build-tools;${ANDROID_BUILD_TOOLS}" "ndk;28.2.13676358" "cmake;3.22.1" \
    >/dev/null

ENV PATH=/opt/android-sdk/build-tools/${ANDROID_BUILD_TOOLS}:$PATH

RUN git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git /opt/flutter \
    && test "$(git -C /opt/flutter rev-parse HEAD)" = "$FLUTTER_COMMIT" \
    && flutter --disable-analytics \
    && dart --disable-analytics \
    && flutter config --android-sdk "$ANDROID_HOME" \
    && flutter precache --linux --android --no-ios --no-web \
    --no-macos --no-windows --no-fuchsia

RUN curl -fsSL -o /usr/local/bin/appimagetool \
    "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage" \
    && echo "${APPIMAGETOOL_SHA256}  /usr/local/bin/appimagetool" | sha256sum -c - \
    && chmod +x /usr/local/bin/appimagetool
