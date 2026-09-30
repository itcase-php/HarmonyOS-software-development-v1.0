cmake_minimum_required(VERSION 3.18)
project(hdm_isolated_jpeg_pdf LANGUAGES C CXX)
include(CTest)
include(FetchContent)
include(ExternalProject)
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
# Upstream explicitly requires a top-level build. Populate, then configure it
# independently; no dependency/target from this prototype is in the Stage app.
set(HDM_JPEG_ARCHIVE "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.4.1/libjpeg-turbo-3.1.4.1.tar.gz" CACHE STRING "Pinned official archive URL or offline file")
FetchContent_Declare(jpeg_source URL "${HDM_JPEG_ARCHIVE}"
    URL_HASH SHA256=ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022
    SOURCE_SUBDIR hdm_population_only)
FetchContent_MakeAvailable(jpeg_source)
set(jpeg_binary "${CMAKE_CURRENT_BINARY_DIR}/jpeg-build")
if(CMAKE_HOST_SYSTEM_PROCESSOR)
    set(hdm_jpeg_processor "${CMAKE_HOST_SYSTEM_PROCESSOR}")
elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(hdm_jpeg_processor "x86_64")
else()
    set(hdm_jpeg_processor "x86")
endif()
set(hdm_jpeg_toolchain "")
if(WIN32)
    set(hdm_jpeg_toolchain "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_CURRENT_SOURCE_DIR}/cmake/windows-host.cmake")
endif()
ExternalProject_Add(jpeg_build SOURCE_DIR "${jpeg_source_SOURCE_DIR}" BINARY_DIR "${jpeg_binary}"
    DOWNLOAD_COMMAND "" INSTALL_COMMAND ""
    CMAKE_ARGS -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_SIMD=OFF -DWITH_JPEG8=ON
        -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DWITH_ARITH_DEC=OFF -DWITH_ARITH_ENC=OFF
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER} -DCMAKE_SYSTEM_PROCESSOR=${hdm_jpeg_processor} ${hdm_jpeg_toolchain}
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    BUILD_BYPRODUCTS "${jpeg_binary}/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX}")
add_library(hdm_jpeg STATIC IMPORTED)
set_target_properties(hdm_jpeg PROPERTIES IMPORTED_LOCATION
    "${jpeg_binary}/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX}")
add_dependencies(hdm_jpeg jpeg_build)

add_library(hdm_jpeg_pdf STATIC src/stream.cpp src/ir.cpp src/prototype.cpp src/jpeg_probe.c src/jpeg_memory.c)
target_include_directories(hdm_jpeg_pdf PUBLIC include PRIVATE src "${jpeg_source_SOURCE_DIR}/src" "${jpeg_binary}")
target_compile_features(hdm_jpeg_pdf PUBLIC cxx_std_17)
target_link_libraries(hdm_jpeg_pdf PUBLIC hdm_jpeg)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(hdm_jpeg_pdf PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
add_executable(hdm_jpeg_pdf_cli src/main.cpp)
target_link_libraries(hdm_jpeg_pdf_cli PRIVATE hdm_jpeg_pdf)
add_executable(hdm_jpeg_pdf_tests tests/core_tests.cpp)
target_link_libraries(hdm_jpeg_pdf_tests PRIVATE hdm_jpeg_pdf)
foreach(case streams ir budgets payload)
    add_test(NAME prototype_${case} COMMAND hdm_jpeg_pdf_tests ${case})
endforeach()
