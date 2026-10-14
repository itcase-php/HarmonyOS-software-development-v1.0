#!/usr/bin/env bash
# Checks the allocation fallback in the Linux host library, not on OHOS.
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo 'Usage: bash check-sal-math.sh SOURCE BUILD_DIRECTORY' >&2
    exit 2
fi
source_dir=$(realpath "$1")
build_dir=$(realpath "$2")
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
make -C "$build_dir" -j4 gb_Side=build Library_sal
g++ -std=c++17 -Wall -Wextra -Werror -DUNX -DLINUX \
    -I"$build_dir/config_build" -I"$source_dir/include" \
    "$script_dir/sal-math-probe.cpp" "$build_dir/instdir_for_build/program/libuno_sal.so.3" \
    -Wl,-rpath,"$build_dir/instdir_for_build/program" -o "$build_dir/sal-math-probe-host"
"$build_dir/sal-math-probe-host"
