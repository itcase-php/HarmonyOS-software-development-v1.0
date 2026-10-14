#!/usr/bin/env bash
# Host-only failure-path check; never substitutes for an OHOS engine test.
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo 'Usage: bash check-lok-host.sh SOURCE OUTPUT_DIRECTORY' >&2
    exit 2
fi
source_dir=$(realpath "$1")
mkdir -p "$2"
output_dir=$(realpath "$2")
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
test ! -e "$output_dir/missing-program"
test ! -e "$output_dir/negative-output.pdf"
g++ -std=c++17 -Wall -Wextra -Werror -isystem "$source_dir/include" \
    "$script_dir/lok-probe/main.cpp" -ldl -o "$output_dir/lok-probe-host"
set +e
"$output_dir/lok-probe-host"
usage_status=$?
"$output_dir/lok-probe-host" "$output_dir/missing-program" \
    "file://$output_dir/profile" "file://$output_dir/input.docx" "file://$output_dir/negative-output.pdf"
missing_status=$?
set -e
test "$usage_status" -eq 64
test "$missing_status" -eq 2
test ! -e "$output_dir/negative-output.pdf"
printf 'PASS: invalid arguments=64; missing engine=2; no output PDF created.\n'
