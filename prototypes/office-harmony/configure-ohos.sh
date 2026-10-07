#!/usr/bin/env bash
# Configure a separate upstream port build; never changes application capabilities.
set -euo pipefail
if [ "$#" -ne 3 ]; then
    echo 'Usage: bash configure-ohos.sh SOURCE SDK_NATIVE BUILD_DIRECTORY' >&2
    exit 2
fi
source_dir=$(realpath "$1")
sdk_dir=$(realpath "$2")
mkdir -p "$3"
build_dir=$(realpath "$3")
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
python3 "$script_dir/check-compiler.py" "$source_dir" "$sdk_dir" > "$build_dir/compiler-prerequisite.json"
for patch_file in "$script_dir"/patches/*.patch; do
    if git -C "$source_dir" apply --check "$patch_file" 2>/dev/null; then
        git -C "$source_dir" apply "$patch_file"
    else
        git -C "$source_dir" apply --reverse --check "$patch_file"
    fi
done
export CC="$sdk_dir/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$sdk_dir/sysroot"
export CXX="$sdk_dir/llvm/bin/clang++ --target=aarch64-linux-ohos --sysroot=$sdk_dir/sysroot -stdlib=libc++"
export AR="$sdk_dir/llvm/bin/llvm-ar"
export RANLIB="$sdk_dir/llvm/bin/llvm-ranlib"
export NM="$sdk_dir/llvm/bin/llvm-nm"
export STRIP="$sdk_dir/llvm/bin/llvm-strip"
export OBJDUMP="$sdk_dir/llvm/bin/llvm-objdump"
# The OHOS fontconfig configure cache relies on these SDK C99 declarations.
# This compiles and links only; device execution remains a separate check.
"$sdk_dir/llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$sdk_dir/sysroot" \
    -std=c11 -Wall -Wextra -Werror "$script_dir/fontconfig-c99-probe.c" \
    -o "$build_dir/fontconfig-c99-probe-arm64"
# An empty target pkg-config search prevents linking Ubuntu libraries into OHOS.
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR="$sdk_dir/sysroot/usr/lib/aarch64-linux-ohos/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$sdk_dir/sysroot"
cd "$build_dir"
exec perl "$source_dir/autogen.sh" \
    --host=aarch64-unknown-linux-ohos --build=x86_64-pc-linux-gnu \
    --enable-headless --disable-gui --without-java --disable-python \
    --disable-gtk3 --disable-kf5 --disable-kf6 --disable-qt5 --disable-qt6 \
    --disable-skia --disable-cups --disable-dbus --disable-dconf \
    --disable-gstreamer-1-0 --disable-pdfium --disable-pdfimport \
    --disable-firebird-sdbc --disable-postgresql-sdbc \
    --disable-odk --disable-online-update --disable-xmlhelp \
    --disable-gpgmepp --without-gssapi --disable-libcmis --without-webdav --with-tls=openssl --enable-openssl --disable-opencl --disable-mariadb-sdbc \
    --disable-lpsolve --disable-coinmp --disable-extensions --with-galleries=no \
    --without-system-libs --without-system-nss --without-system-fontconfig --without-system-freetype --without-myspell-dicts --without-fonts \
    --disable-mergelibs --disable-symbols --with-parallelism=4 \
    --with-locales='en zh' \
    --with-build-platform-configure-options='--disable-gui --without-java --disable-python --disable-gtk3 --disable-kf5 --disable-kf6 --disable-qt5 --disable-qt6 --disable-skia --disable-cups --disable-dbus --disable-dconf --disable-gstreamer-1-0 --disable-pdfium --disable-pdfimport --disable-firebird-sdbc --disable-postgresql-sdbc --disable-odk --disable-online-update --disable-xmlhelp --disable-gpgmepp --without-gssapi --disable-libcmis --without-webdav --with-tls=openssl --enable-openssl --disable-opencl --disable-mariadb-sdbc --disable-lpsolve --disable-coinmp --disable-extensions --with-galleries=no --without-system-libs --without-system-nss --without-myspell-dicts --without-fonts --disable-symbols --with-parallelism=4 --with-system-fontconfig --with-system-freetype PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig PKG_CONFIG_SYSROOT_DIR=/'
