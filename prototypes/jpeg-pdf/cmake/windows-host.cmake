# Upstream's 3.1.4.1 CMakeLists expands CMAKE_SYSTEM_PROCESSOR without quotes.
# Ninja/MinGW on Windows may leave it empty; this host-only toolchain identifies it.
set(CMAKE_SYSTEM_NAME Windows)
if(CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(CMAKE_SYSTEM_PROCESSOR x86)
else()
    set(CMAKE_SYSTEM_PROCESSOR x86_64)
endif()
