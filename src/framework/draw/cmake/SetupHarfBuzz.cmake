# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-CLA-applies
#
# MuseScore
# Music Composition & Notation
#
# Copyright (C) 2024 MuseScore Limited
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

if (MUE_COMPILE_USE_SYSTEM_HARFBUZZ)
    find_package(HarfBuzz)

    if (HarfBuzz_FOUND)
        message(STATUS "Found HarfBuzz")

        # See HarfBuzz's harfbuzz-config.cmake, which is quite minimalistic
        set(HARFBUZZ_LIBRARIES harfbuzz::harfbuzz)
        set(HARFBUZZ_INCLUDE_DIRS ${HARFBUZZ_INCLUDE_DIR})

        return()
    else()
        message(WARNING "Set MUE_COMPILE_USE_SYSTEM_HARFBUZZ=ON, but system harfbuzz not found, built-in will be used")
    endif()
endif()

# If not MUE_COMPILE_USE_SYSTEM_HARFBUZZ, or if it was not found,
# download and build harfbuzz

if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND SCORE_RENDER_QT_TARGET_ROOT)
    set(qt_harfbuzz_include_dir ${SCORE_RENDER_QT_TARGET_ROOT}/include/QtHarfbuzz/harfbuzz)
    set(qt_harfbuzz_debug_lib ${SCORE_RENDER_QT_TARGET_ROOT}/lib/libQt6BundledHarfbuzz_debug.a)
    set(qt_harfbuzz_release_lib ${SCORE_RENDER_QT_TARGET_ROOT}/lib/libQt6BundledHarfbuzz.a)
    if(EXISTS /opt/homebrew/include/harfbuzz/hb-ft.h)
        set(qt_harfbuzz_ft_include_dir /opt/homebrew/include/harfbuzz)
    elseif(EXISTS /usr/local/include/harfbuzz/hb-ft.h)
        set(qt_harfbuzz_ft_include_dir /usr/local/include/harfbuzz)
    else()
        find_path(qt_harfbuzz_ft_include_dir hb-ft.h
            HINTS
                /opt/homebrew/include
                /usr/local/include
            PATH_SUFFIXES
                harfbuzz
                include/harfbuzz
        )
    endif()

    if(EXISTS ${qt_harfbuzz_include_dir}/hb.h AND EXISTS ${qt_harfbuzz_release_lib})
        add_library(muse_qt_bundled_harfbuzz STATIC IMPORTED GLOBAL)
        set_target_properties(muse_qt_bundled_harfbuzz PROPERTIES
            IMPORTED_CONFIGURATIONS "Debug;Release;RelWithDebInfo;MinSizeRel"
            IMPORTED_LOCATION_DEBUG ${qt_harfbuzz_debug_lib}
            IMPORTED_LOCATION_RELEASE ${qt_harfbuzz_release_lib}
            IMPORTED_LOCATION_RELWITHDEBINFO ${qt_harfbuzz_release_lib}
            IMPORTED_LOCATION_MINSIZEREL ${qt_harfbuzz_release_lib}
            INTERFACE_INCLUDE_DIRECTORIES ${qt_harfbuzz_include_dir}
        )

        set(HARFBUZZ_LIBRARIES muse_qt_bundled_harfbuzz)
        set(HARFBUZZ_INCLUDE_DIRS ${qt_harfbuzz_include_dir})
        if(qt_harfbuzz_ft_include_dir)
            list(APPEND HARFBUZZ_INCLUDE_DIRS ${qt_harfbuzz_ft_include_dir})
        endif()
        message(STATUS "Using Qt bundled HarfBuzz from ${SCORE_RENDER_QT_TARGET_ROOT}")
        return()
    endif()
endif()

set(REMOTE_ROOT_URL https://raw.githubusercontent.com/musescore/muse_deps/main)
set(remote_url ${REMOTE_ROOT_URL}/harfbuzz/12.3.0)
set(local_path ${PROJECT_BINARY_DIR}/_deps/harfbuzz)
if (NOT EXISTS ${local_path}/harfbuzz.cmake)
    file(MAKE_DIRECTORY ${local_path})
    file(DOWNLOAD ${remote_url}/harfbuzz.cmake ${local_path}/harfbuzz.cmake
        HTTPHEADER "Cache-Control: no-cache"
    )
endif()

include(${local_path}/harfbuzz.cmake)

# func from ${name}.cmake)
cmake_language(CALL harfbuzz_Populate ${remote_url} ${local_path} "source" "" "")

set(HB_HAVE_FREETYPE ON)

add_subdirectory(${local_path}/harfbuzz harfbuzz)

target_no_warning(harfbuzz -Wno-conversion)
target_no_warning(harfbuzz -Wno-unused-parameter)
target_no_warning(harfbuzz -Wno-unused-variable)
target_no_warning(harfbuzz -WMSVC-no-hides-previous)
target_no_warning(harfbuzz -WMSVC-no-unreachable)

#add_subdirectory(thirdparty/msdfgen)

set(HARFBUZZ_LIBRARIES harfbuzz)
set(HARFBUZZ_INCLUDE_DIRS ${local_path}/harfbuzz/harfbuzz/src)
