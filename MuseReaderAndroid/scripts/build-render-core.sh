#!/bin/sh
# Builds the shared MuseScore render core (sandbox/engraving) for Android arm64-v8a.
# Output: build-aria-android-arm64/libMuseScoreRenderCore.a plus the engine module
# archives, and score_render_probe for adb checks.
#
# Override any path with the matching environment variable.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
NDK="${ANDROID_NDK_ROOT:-$SDK/ndk/27.2.12479018}"   # r27c, what Qt 6.11 is built with
QT_ANDROID="${QT_ANDROID:-$HOME/Qt/android/6.11.1/android_arm64_v8a}"
QT_HOST="${QT_HOST:-$HOME/Qt/android/6.11.1/macos}"  # must be the same Qt version
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-aria-android-arm64}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

cmake -S "$REPO_ROOT/sandbox/engraving" -B "$BUILD_DIR" -G Ninja -Wno-dev \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_TOOLCHAIN_FILE="$QT_ANDROID/lib/cmake/Qt6/qt.toolchain.cmake" \
  -DQT_CHAINLOAD_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-28 \
  -DANDROID_STL=c++_shared \
  -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
  -DANDROID_SDK_ROOT="$SDK" \
  -DANDROID_NDK_ROOT="$NDK" \
  -DQT_HOST_PATH="$QT_HOST" \
  -DSCORE_RENDER_QT_TARGET_ROOT="$QT_ANDROID" \
  -DSCORE_RENDER_QT_HOST_ROOT="$QT_HOST"

cmake --build "$BUILD_DIR" --target MuseScoreRenderCore score_render_probe
