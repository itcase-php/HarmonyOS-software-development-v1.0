#!/usr/bin/env bash
# Prepare a copy for device probing; never strip or alter the pinned build output.
set -euo pipefail
base="${HOME}/.cache/hdm-office/26.2.6.2"
sdk="${HOME}/.cache/hdm-office/sdk/command-line-tools/sdk/default/openharmony/native"
stage="$base/device-runtime"
test -d "$base/build-arm64/instdir/program"
test ! -e "$stage"
mkdir -p "$stage"
cp -a "$base/build-arm64/instdir/." "$stage/"
cp "$sdk/llvm/lib/aarch64-linux-ohos/libc++_shared.so" "$stage/program/"
cp "$base/lok-probe-arm64/hdm_office_lok_probe" "$stage/"
while IFS= read -r -d '' library; do
  if file -b "$library" | grep -q '^ELF'; then
    "$sdk/llvm/bin/llvm-strip" --strip-debug "$library"
  fi
done < <(find "$stage/program" -maxdepth 1 -type f -print0)
mkdir -p "$stage/fonts" "$stage/font-cache"
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf "$stage/fonts/"
cp /usr/share/doc/fonts-dejavu-core/copyright "$stage/fonts/DejaVu-LICENSE.txt"
cat > "$stage/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/data/local/tmp/hdm-office-26.2.6.2/fonts</dir>
  <dir>/system/fonts</dir>
  <cachedir>/data/local/tmp/hdm-office-26.2.6.2/font-cache</cachedir>
</fontconfig>
EOF
du -sh "$stage"
tar -C "$stage" -czf /mnt/d/HarmonyOS/harmonyOS/tmp/offline-engines/office-runtime-26.2.6.2.tar.gz .
