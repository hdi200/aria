#!/bin/sh
# Builds engine/ into libaria_engine.so (the render core plus its Android Qt setup) and
# gathers it with the Qt libraries the app ships into build-aria-android-arm64/jniLibs,
# which the app's Gradle build packages. Run build-render-core.sh first.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
NDK="${ANDROID_NDK_ROOT:-$SDK/ndk/27.2.12479018}"
QT_ANDROID="${QT_ANDROID:-$HOME/Qt/android/6.11.1/android_arm64_v8a}"
CORE_DIR="${BUILD_DIR:-$REPO_ROOT/build-aria-android-arm64}"
ENGINE_BUILD_DIR="$CORE_DIR/engine"
JNI_LIBS_DIR="$CORE_DIR/jniLibs/arm64-v8a"

cmake -S "$REPO_ROOT/MuseReaderAndroid/engine" -B "$ENGINE_BUILD_DIR" -G Ninja -Wno-dev \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-28 \
  -DANDROID_STL=c++_shared \
  -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
  -DARIA_QT_ANDROID_DIR="$QT_ANDROID" \
  -DARIA_RENDER_CORE_BUILD_DIR="$CORE_DIR"
cmake --build "$ENGINE_BUILD_DIR"

# Qt libraries the engine links, plus the offscreen platform plugin. Plugins keep Qt's
# Android file names so Qt finds them in the app's library folder.
rm -rf "$JNI_LIBS_DIR"
mkdir -p "$JNI_LIBS_DIR"
"$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip" --strip-unneeded \
  -o "$JNI_LIBS_DIR/libaria_engine.so" "$ENGINE_BUILD_DIR/libaria_engine.so"
for module in Core Gui Svg Qml QmlMeta QmlModels QmlWorkerScript Network Quick OpenGL Widgets; do
  cp "$QT_ANDROID/lib/libQt6${module}_arm64-v8a.so" "$JNI_LIBS_DIR/"
done
cp "$QT_ANDROID/plugins/platforms/libplugins_platforms_qoffscreen_arm64-v8a.so" "$JNI_LIBS_DIR/"
echo "Native libraries ready in $JNI_LIBS_DIR"
