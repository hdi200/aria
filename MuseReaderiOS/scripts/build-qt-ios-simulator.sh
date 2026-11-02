#!/bin/sh
# Builds Qt 6.11.0 for the arm64 iOS Simulator, so Aria runs natively on
# arm64-only Simulator runtimes (iOS 27 and later, including iPhone Duo).
# Qt's own iOS SDK ships its Simulator slice as x86_64 only (QTBUG-101276).
#
# Only the modules the render core needs are built, Release only:
# qtbase, qtsvg and qtdeclarative. qtdeclarative needs the qsb shader tool,
# which the macOS Qt does not include, so qtshadertools is built for the host
# into the work folder first.
#
#   QT_HOST_SDK_DIR=~/Qt/6.11.0/macos \
#   QT_SIMULATOR_SDK_DIR=~/Qt/6.11.0/ios-simulator \
#   ./build-qt-ios-simulator.sh
#
# Then set MUSEREADER_QT_IOS_SIMULATOR_SDK_DIR in Local.xcconfig to
# QT_SIMULATOR_SDK_DIR. The work folder (sources and builds, about 5 GB) can
# be deleted afterwards.
set -eu

QT_VERSION=6.11.0
QT_HOST_SDK_DIR="${QT_HOST_SDK_DIR:-$HOME/Qt/$QT_VERSION/macos}"
QT_SIMULATOR_SDK_DIR="${QT_SIMULATOR_SDK_DIR:-$HOME/Qt/$QT_VERSION/ios-simulator}"
WORK_DIR="${WORK_DIR:-$(mktemp -d -t aria-qt-simulator)}"
JOBS="$(sysctl -n hw.ncpu)"
SOURCE_URL="https://download.qt.io/official_releases/qt/${QT_VERSION%.*}/$QT_VERSION/submodules"

echo "Work folder: $WORK_DIR"
mkdir -p "$WORK_DIR/src" "$WORK_DIR/build"

fetch() {
    module="$1"
    source_dir="$WORK_DIR/src/$module-everywhere-src-$QT_VERSION"
    if [ -d "$source_dir" ]; then
        return
    fi
    archive="$WORK_DIR/src/$module.tar.xz"
    curl -fsSL -o "$archive" "$SOURCE_URL/$module-everywhere-src-$QT_VERSION.tar.xz"
    expected="$(grep " $module-everywhere-src-$QT_VERSION.tar.xz\$" "$WORK_DIR/src/md5sums.txt" | cut -d' ' -f1)"
    if [ "$(md5 -q "$archive")" != "$expected" ]; then
        echo "error: checksum mismatch for $module" >&2
        exit 1
    fi
    tar xf "$archive" -C "$WORK_DIR/src"
    rm "$archive"
}

build_and_install() {
    cmake --build . --parallel "$JOBS"
    cmake --install .
}

curl -fsSL -o "$WORK_DIR/src/md5sums.txt" "$SOURCE_URL/md5sums.txt"
for module in qtbase qtsvg qtdeclarative qtshadertools; do
    fetch "$module"
done

# Apple clang 21 reports __yield as a builtin on arm64 but it needs
# <arm_acle.h>; use __builtin_arm_yield instead.
sed -i '' 's/^#if __has_builtin(__yield)$/#if __has_builtin(__yield) \&\& !defined(Q_PROCESSOR_ARM)  \/\/ Aria: Apple clang 21 needs <arm_acle.h> for __yield/' \
    "$WORK_DIR/src/qtbase-everywhere-src-$QT_VERSION/src/corelib/thread/qyieldcpu.h"

mkdir -p "$WORK_DIR/build/qtbase"
cd "$WORK_DIR/build/qtbase"
"$WORK_DIR/src/qtbase-everywhere-src-$QT_VERSION/configure" \
    -platform macx-ios-clang -sdk iphonesimulator \
    -release -static -nomake examples -nomake tests \
    -prefix "$QT_SIMULATOR_SDK_DIR" \
    -qt-host-path "$QT_HOST_SDK_DIR" \
    -- -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DFEATURE_framework=ON
build_and_install

mkdir -p "$WORK_DIR/build/qtsvg"
cd "$WORK_DIR/build/qtsvg"
"$QT_SIMULATOR_SDK_DIR/bin/qt-configure-module" "$WORK_DIR/src/qtsvg-everywhere-src-$QT_VERSION"
build_and_install

# Host qsb, installed into the work folder so the macOS Qt is left as is.
HOST_TOOLS_DIR="$WORK_DIR/host-tools"
mkdir -p "$WORK_DIR/build/host-shadertools"
cd "$WORK_DIR/build/host-shadertools"
"$QT_HOST_SDK_DIR/bin/qt-configure-module" "$WORK_DIR/src/qtshadertools-everywhere-src-$QT_VERSION" \
    -- -DCMAKE_INSTALL_PREFIX="$HOST_TOOLS_DIR" -DCMAKE_OSX_ARCHITECTURES=arm64
build_and_install
# qsb looks for QtGui next to itself; point it at the macOS Qt.
install_name_tool -add_rpath "$QT_HOST_SDK_DIR/lib" "$HOST_TOOLS_DIR/bin/qsb"
codesign --force --sign - "$HOST_TOOLS_DIR/bin/qsb"

mkdir -p "$WORK_DIR/build/qtdeclarative"
cd "$WORK_DIR/build/qtdeclarative"
"$QT_SIMULATOR_SDK_DIR/bin/qt-configure-module" "$WORK_DIR/src/qtdeclarative-everywhere-src-$QT_VERSION" \
    -- -DQt6ShaderToolsTools_DIR="$HOST_TOOLS_DIR/lib/cmake/Qt6ShaderToolsTools"
build_and_install

if [ ! -f "$QT_SIMULATOR_SDK_DIR/lib/QtQuick.framework/QtQuick" ]; then
    echo "error: Qt Quick was not built; check the qtdeclarative configure output" >&2
    exit 1
fi

echo "Installed Qt for the arm64 iOS Simulator in $QT_SIMULATOR_SDK_DIR"
echo "You can delete $WORK_DIR"
