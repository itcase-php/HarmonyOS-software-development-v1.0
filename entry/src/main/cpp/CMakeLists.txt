# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(harmonyOS)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

include(${CMAKE_CURRENT_SOURCE_DIR}/generated/engine_sources.cmake)
add_library(entry SHARED napi_init.cpp napi/native_bridge.cpp core/engine_registry.cpp ${HDM_ENGINE_SOURCES})
target_compile_features(entry PRIVATE cxx_std_17)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(entry PRIVATE -Wall -Wextra -Wpedantic)
endif()
target_link_libraries(entry PUBLIC libace_napi.z.so)

# Off by default: host contract tests and their mock NAPI never enter the HAP.
option(HDM_BUILD_HOST_TESTS "Build host-only native contract tests" OFF)
if(HDM_BUILD_HOST_TESTS)
    if(CMAKE_CROSSCOMPILING OR CMAKE_SYSTEM_NAME STREQUAL "OHOS")
        message(FATAL_ERROR "Configure cpp/tests separately with a host compiler")
    endif()
    enable_testing()
    add_subdirectory(tests)
endif()
