# Release build environment. The toolchain is pinned here (base image, apt
# snapshot, Flutter, appimagetool, every Android SDK package); what the build
# then downloads itself (Maven dependencies, Flutter's engine artifacts) is not.
FROM ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401

# The AppImage bundles libraries from this snapshot, and nothing updates them on
# a user's machine: move it forward at every release (docs/RELEASING.md).
ARG UBUNTU_SNAPSHOT=20261001T000000Z
ARG FLUTTER_VERSION=3.47.7
ARG FLUTTER_COMMIT=abaf9c523780a608bd46686fd5e53740a07077f8
ARG APPIMAGETOOL_VERSION=1.9.1
ARG APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
ARG ANDROID_CMDLINE_TOOLS_BUILD=16111833
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8
ARG ANDROID_BUILD_TOOLS=36.0.0
# Must match what Gradle wants, or the build fails: it may not download its own.
ARG ANDROID_NDK=28.2.13676358
ARG ANDROID_CMAKE=3.22.1

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

# sdkmanager is not used to install anything: the shim in these tools downloads
# an installer that nothing pins, and takes the current revision of a package.
# The tools stay for `flutter doctor`.
RUN curl -fsSL -o /tmp/cmdline-tools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_BUILD}_latest.zip" \
    && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

# The rest of the SDK is unpacked from the packages' zips, each checked against
# its sha256. The zip of a package is named in its <url> in
# https://dl.google.com/android/repository/repository2-3.xml. The platforms are
# the compile SDK levels of the app (37.0) and of its plugins (36 and 35).
COPY android_sdk_package.sh /usr/local/bin/android_sdk_package
RUN android_sdk_package platform-35_r02.zip \
    0988cacad01b38a18a47bac14a0695f246bc76c1b06c0eeb8eb0dc825ab0c8e0 \
    android-35 platforms/android-35
RUN android_sdk_package platform-36_r02.zip \
    37607369a28c5b640b3a7998868d45898ebcb777565a0e85f9acf36f29631d2e \
    android-36 platforms/android-36
RUN android_sdk_package platform-37.0_r02.zip \
    840b23e827f96e64aea4c89a1194aac3dc5f6bad37edb231c5c795d890330e8d \
    android-37.0 platforms/android-37.0
RUN android_sdk_package platform-tools_r37.0.1-linux.zip \
    d230f13842f60f782a8645f9c813f8f845bf36089ea7289f28c48f17979313f1 \
    platform-tools platform-tools
RUN android_sdk_package build-tools_r36_linux.zip \
    5d9ac77fb6ff43d9da518a337b4fcf8f9097113df531d99ccefe80ef7ce8250b \
    android-16 "build-tools/${ANDROID_BUILD_TOOLS}"
RUN android_sdk_package cmake-3.22.1-linux.zip \
    9196644852a978012caf7a4067ba1898debf6cc204c3341562771e31080d6869 \
    . "cmake/${ANDROID_CMAKE}"
RUN android_sdk_package android-ndk-r28c-linux.zip \
    dfb20d396df28ca02a8c708314b814a4d961dc9074f9a161932746f815aa552f \
    android-ndk-r28c "ndk/${ANDROID_NDK}"

# That is everything the app's build uses, so Gradle may not install anything:
# it would take a missing package at the current revision, unpinned.
ENV GRADLE_USER_HOME=/opt/gradle
RUN mkdir -p "$GRADLE_USER_HOME" \
    && echo "android.builder.sdkDownload=false" >"$GRADLE_USER_HOME/gradle.properties"

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
