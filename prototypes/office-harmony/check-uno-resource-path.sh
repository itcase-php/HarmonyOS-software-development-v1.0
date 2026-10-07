#!/usr/bin/env bash
# Compile the patched resource-path function on the host with only its OHOS branch selected.
set -euo pipefail
test "$#" -eq 3
source_dir=$(realpath "$1")
build_dir=$(realpath "$2")
mkdir -p "$3"
output_dir=$(realpath "$3")
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
host_libs="$build_dir/instdir_for_build/program"
compile_path_test() {
g++ -std=c++20 -Wall -Wextra -Werror -D__OHOS__ -DLINUX -DUNX -DGCC -DLIBO_INTERNAL_ONLY \
  -I"$build_dir/config_build" -I"$build_dir/config_host" -I"$source_dir/include" \
  -I"$source_dir/cppuhelper/source" \
  -I"$build_dir/workdir_for_build/UnoApiHeadersTarget/udkapi/normal" \
  "$script_dir/uno-resource-path-test.cpp" "$1" \
  -L"$host_libs" -Wl,-rpath,"$host_libs" \
  -l:libuno_cppuhelpergcc3.so.3 -l:libuno_cppu.so.3 -l:libuno_sal.so.3 \
  -o "$output_dir/uno-resource-path-test"
}
git -C "$source_dir" show HEAD:cppuhelper/source/paths.cxx > "$output_dir/unpatched-paths.cxx"
compile_path_test "$output_dir/unpatched-paths.cxx"
if LD_LIBRARY_PATH="$host_libs" "$output_dir/uno-resource-path-test" valid; then
  echo 'Unpatched source unexpectedly passed the separated-resource regression' >&2
  exit 1
fi
compile_path_test "$source_dir/cppuhelper/source/paths.cxx"
for mode in valid invalid missing; do
  LD_LIBRARY_PATH="$host_libs" "$output_dir/uno-resource-path-test" "$mode"
done
printf 'PASS: unpatched source fails the regression; patched source uses explicit resource URI and rejects missing/non-file URI. Host branch test only.\n'
