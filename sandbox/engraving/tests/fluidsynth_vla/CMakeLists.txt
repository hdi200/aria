cmake_minimum_required(VERSION 3.26)
project(fluidsynth_vla_regression LANGUAGES C)

# Standalone: exercise the same NO_GLIB allocation path as the iOS sampler,
# without needing Qt or building the engraving engine.
set(FLUID_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../src/framework/audio/thirdparty/fluidsynth/fluidsynth-2.3.3")
add_executable(fluidsynth_vla_test vla_test.c)
target_include_directories(fluidsynth_vla_test PRIVATE
    "${FLUID_DIR}/include" "${FLUID_DIR}/src/external" "${FLUID_DIR}/src/utils")
target_compile_definitions(fluidsynth_vla_test PRIVATE NO_GLIB NO_THREADS)
if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(fluidsynth_vla_test PRIVATE -O0 -g -fsanitize=address)
    target_link_options(fluidsynth_vla_test PRIVATE -fsanitize=address)
endif()
enable_testing()
add_test(NAME fluidsynth_vla_test COMMAND fluidsynth_vla_test)
