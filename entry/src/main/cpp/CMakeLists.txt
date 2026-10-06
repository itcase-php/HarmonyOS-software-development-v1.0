# the minimum version of CMake.
cmake_minimum_required(VERSION 3.18)
project(harmonyOS)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

include(${CMAKE_CURRENT_SOURCE_DIR}/generated/engine_sources.cmake)
set(HDM_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../")
include(${CMAKE_CURRENT_SOURCE_DIR}/production/build_manifest.cmake)
hdm_create_build_manifest("${HDM_REPOSITORY_ROOT}")
set(HDM_PROTOTYPE_ROOT "${HDM_REPOSITORY_ROOT}/prototypes/jpeg-pdf")
include(FetchContent)
include(ExternalProject)
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
set(HDM_JPEG_ARCHIVE "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.4.1/libjpeg-turbo-3.1.4.1.tar.gz"
    CACHE STRING "Pinned official JPEG archive URL or offline file")
FetchContent_Declare(hdm_jpeg_source URL "${HDM_JPEG_ARCHIVE}"
    URL_HASH SHA256=ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022
    SOURCE_SUBDIR hdm_population_only)
FetchContent_MakeAvailable(hdm_jpeg_source)
set(HDM_JPEG_BINARY "${CMAKE_CURRENT_BINARY_DIR}/hdm-jpeg-build")
ExternalProject_Add(hdm_jpeg_build SOURCE_DIR "${hdm_jpeg_source_SOURCE_DIR}" BINARY_DIR "${HDM_JPEG_BINARY}"
    DOWNLOAD_COMMAND "" INSTALL_COMMAND ""
    CMAKE_ARGS -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_SIMD=OFF
        -DWITH_JPEG8=ON -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DWITH_ARITH_DEC=OFF -DWITH_ARITH_ENC=OFF
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DOHOS_SDK_NATIVE=${OHOS_SDK_NATIVE} -DHMOS_SDK_NATIVE=${HMOS_SDK_NATIVE} -DOHOS_ARCH=${OHOS_ARCH}
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    BUILD_BYPRODUCTS "${HDM_JPEG_BINARY}/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX}")
add_library(hdm_jpeg STATIC IMPORTED)
set_target_properties(hdm_jpeg PROPERTIES IMPORTED_LOCATION
    "${HDM_JPEG_BINARY}/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX}")
add_dependencies(hdm_jpeg hdm_jpeg_build)
add_library(hdm_jpeg_pdf STATIC
    ${HDM_PROTOTYPE_ROOT}/src/stream.cpp ${HDM_PROTOTYPE_ROOT}/src/ir.cpp
    ${HDM_PROTOTYPE_ROOT}/src/prototype.cpp ${HDM_PROTOTYPE_ROOT}/src/jpeg_probe.c
    ${HDM_PROTOTYPE_ROOT}/src/jpeg_memory.c)
target_include_directories(hdm_jpeg_pdf PUBLIC ${HDM_PROTOTYPE_ROOT}/include
    PRIVATE ${HDM_PROTOTYPE_ROOT}/src "${hdm_jpeg_source_SOURCE_DIR}/src" "${HDM_JPEG_BINARY}")
target_link_libraries(hdm_jpeg_pdf PUBLIC hdm_jpeg)
target_compile_features(hdm_jpeg_pdf PUBLIC cxx_std_17)
add_library(entry SHARED napi_init.cpp napi/native_bridge.cpp napi/production_napi.cpp napi/result_serializer.cpp core/engine_registry.cpp
    production/runtime.cpp production/sha256.cpp production/output_validator.cpp ${HDM_ENGINE_SOURCES})
target_compile_features(entry PRIVATE cxx_std_17)
target_compile_definitions(entry PRIVATE HDM_PRODUCTION_NATIVE=1)
target_compile_definitions(entry PRIVATE $<$<CONFIG:Debug>:HDM_NATIVE_DEBUG=1>)
target_include_directories(entry PRIVATE "${HDM_BUILD_MANIFEST_INCLUDE}")
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(entry PRIVATE -Wall -Wextra -Wpedantic)
endif()
target_link_libraries(entry PUBLIC libace_napi.z.so hdm_jpeg_pdf)

# Off by default: host contract tests and their mock NAPI never enter the HAP.
option(HDM_BUILD_HOST_TESTS "Build host-only native contract tests" OFF)
if(HDM_BUILD_HOST_TESTS)
    if(CMAKE_CROSSCOMPILING OR CMAKE_SYSTEM_NAME STREQUAL "OHOS")
        message(FATAL_ERROR "Configure cpp/tests separately with a host compiler")
    endif()
    enable_testing()
    add_subdirectory(tests)
endif()
