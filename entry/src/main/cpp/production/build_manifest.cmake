# The engine stamp hashes actual source bytes, pinned dependency and build inputs.
# It is a build-manifest digest, not a digest of the resulting shared library.
function(hdm_create_build_manifest repository_root)
    file(REAL_PATH "${repository_root}" repository_root)
    file(GLOB_RECURSE task_sources CONFIGURE_DEPENDS
        "${repository_root}/entry/src/main/cpp/core/*.h"
        "${repository_root}/entry/src/main/cpp/core/*.cpp"
        "${repository_root}/entry/src/main/cpp/napi/*.h"
        "${repository_root}/entry/src/main/cpp/napi/*.cpp"
        "${repository_root}/entry/src/main/cpp/production/*.h"
        "${repository_root}/entry/src/main/cpp/production/*.cpp"
        "${repository_root}/entry/src/main/cpp/production/*.cmake"
        "${repository_root}/entry/src/main/cpp/engines/image/*.cpp"
        "${repository_root}/entry/src/main/cpp/generated/*.h"
        "${repository_root}/prototypes/jpeg-pdf/src/*.h"
        "${repository_root}/prototypes/jpeg-pdf/src/*.c"
        "${repository_root}/prototypes/jpeg-pdf/src/*.cpp"
        "${repository_root}/prototypes/jpeg-pdf/include/*.h")
    list(APPEND task_sources "${repository_root}/entry/src/main/cpp/CMakeLists.txt"
        "${repository_root}/shared/format-registry/debug-routes.json"
        "${repository_root}/shared/format-registry/conversion-matrix.json")
    list(SORT task_sources)
    foreach(task_source IN LISTS task_sources)
        if(NOT task_source MATCHES "\\.cmake$|CMakeLists\\.txt$")
            set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${task_source}")
        endif()
    endforeach()
    set(task_manifest "schema=1\nengine=image\nversion=1.1.0-experimental\n")
    string(APPEND task_manifest "jpeg=3.1.4.1\njpegArchiveSha256=ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022\n")
    string(APPEND task_manifest "jpegOptions=static,jpeg8,no-simd,no-arithmetic,no-tools\n")
    string(APPEND task_manifest "system=${CMAKE_SYSTEM_NAME}\nabi=${OHOS_ARCH}/${CMAKE_SYSTEM_PROCESSOR}\n")
    string(APPEND task_manifest "compiler=${CMAKE_CXX_COMPILER_ID}/${CMAKE_CXX_COMPILER_VERSION}\nmode=${CMAKE_BUILD_TYPE}\n")
    string(APPEND task_manifest "flags=${CMAKE_CXX_FLAGS}|${CMAKE_CXX_FLAGS_DEBUG}|${CMAKE_CXX_FLAGS_RELEASE}\n")
    if(EXISTS "${CMAKE_TOOLCHAIN_FILE}")
        file(SHA256 "${CMAKE_TOOLCHAIN_FILE}" task_digest)
        string(APPEND task_manifest "toolchainSha256=${task_digest}\n")
    endif()
    if(EXISTS "${OHOS_SDK_NATIVE}/oh-uni-package.json")
        file(SHA256 "${OHOS_SDK_NATIVE}/oh-uni-package.json" task_digest)
        string(APPEND task_manifest "sdkMetadataSha256=${task_digest}\n")
    endif()
    foreach(task_source IN LISTS task_sources)
        file(RELATIVE_PATH task_relative "${repository_root}" "${task_source}")
        file(SHA256 "${task_source}" task_digest)
        string(APPEND task_manifest "${task_relative}=${task_digest}\n")
    endforeach()
    string(SHA256 task_build_hash "${task_manifest}")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/hdm-manifest")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/hdm-manifest/image-build-manifest.txt" "${task_manifest}")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/hdm-manifest/hdm_build_manifest.h"
        "#pragma once\nnamespace hdm { inline constexpr const char* kImageBuildHash = \"${task_build_hash}\"; }\n")
    set(HDM_BUILD_MANIFEST_INCLUDE "${CMAKE_CURRENT_BINARY_DIR}/hdm-manifest" PARENT_SCOPE)
endfunction()
