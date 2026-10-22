cmake_minimum_required(VERSION 3.22)

# libaria_engine.so: the shared render core for the Android app, plus its Android Qt
# setup. Swift links it and calls it through C++ interop (Aria/Sources/AriaEngine).
# Built by ../scripts/build-engine.sh after ../scripts/build-render-core.sh.

project(aria_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ARIA_QT_ANDROID_DIR "" CACHE PATH "Qt for Android arm64-v8a root")
set(ARIA_RENDER_CORE_BUILD_DIR "" CACHE PATH "Render core build from scripts/build-render-core.sh")

set(engine_source_dir ${CMAKE_CURRENT_LIST_DIR}/../../sandbox/engraving)
# Shared with the iOS app: its zip reader for MSCZ/MXL packages.
set(ios_bridge_dir ${CMAKE_CURRENT_LIST_DIR}/../../MuseReaderiOS/MuseReaderiOS/Bridge)
set(core ${ARIA_RENDER_CORE_BUILD_DIR})

foreach(archive libMuseScoreRenderCore.a musicxml/libiex_musicxml_arm64-v8a.a
        engraving/libengraving_arm64-v8a.a draw/libmuse_draw_arm64-v8a.a global/libmuse_global_arm64-v8a.a)
    if(NOT EXISTS ${core}/${archive})
        message(FATAL_ERROR "Missing ${archive}; run scripts/build-render-core.sh first.")
    endif()
endforeach()

set(qt_libraries)
foreach(module Widgets Quick OpenGL Svg Gui Qml Network Core)
    list(APPEND qt_libraries ${ARIA_QT_ANDROID_DIR}/lib/libQt6${module}_arm64-v8a.so)
endforeach()

add_library(aria_engine SHARED
    aria_engine_android.cpp
    aria_audio_output.cpp
    ${ios_bridge_dir}/MSRZipArchive.cpp
)

target_include_directories(aria_engine PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
    ${engine_source_dir}
    ${ios_bridge_dir}
    ${CMAKE_CURRENT_LIST_DIR}/../../src/framework/audio/thirdparty/fluidsynth/fluidsynth-2.3.3/include
    ${ARIA_QT_ANDROID_DIR}/include
    ${ARIA_QT_ANDROID_DIR}/include/QtCore
    ${ARIA_QT_ANDROID_DIR}/include/QtGui
)

# The whole render core is linked in, since Swift calls into it directly. The MusicXML
# module registers itself from static initializers, so it is linked whole too.
target_link_libraries(aria_engine PRIVATE
    -Wl,--whole-archive ${core}/libMuseScoreRenderCore.a ${core}/musicxml/libiex_musicxml_arm64-v8a.a -Wl,--no-whole-archive
    ${core}/engraving/libengraving_arm64-v8a.a
    ${core}/draw/libmuse_draw_arm64-v8a.a
    ${core}/global/libmuse_global_arm64-v8a.a
    ${qt_libraries}
    z dl GLESv2 EGL log atomic m aaudio
)

target_link_options(aria_engine PRIVATE "-Wl,-rpath-link,${ARIA_QT_ANDROID_DIR}/lib")
