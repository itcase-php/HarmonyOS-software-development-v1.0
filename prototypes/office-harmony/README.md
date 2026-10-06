# Office 鸿蒙工具链前置验证

本目录只验证工具链、ABI 和上游编译器前置条件，不提供 OfficeConverter，不发布转换能力。DOCX/PPTX 真机转换尚未执行。

## 本轮环境

- 用户提供 `commandline-tools-linux-x64-26.0.0.851.zip`；本地 SHA-256：`ab604bd92721d5cbcafd154e6461d46b9f1b105e7b89eab04a9d046681198082`。
- 归档中的 Native 元数据：API 26、26.0.0.105、Release；Linux 编译器 OHOS Clang 15.0.4。
- WSL Ubuntu 26.04.1，安装 Autoconf、Automake、Libtool、CMake、Ninja、GCC/G++、Bison、Flex、gperf、gettext、NASM、Python 及下载/归档工具。宿主 GCC 不用于生成鸿蒙产物。
- SDK 单独解压到缓存，未覆盖 DevEco 的 Windows SDK。清除本次进程 PATH 中继承的 Windows 工具路径，避免上游把 Linux 宿主识别为 Windows 构建辅助环境。

## 重现最小编译

在 WSL Bash 中执行，SDK 指向该归档中的 `sdk/default/openharmony/native`，源码目录指向此目录：

```bash
cmake -S "$PROBE_SOURCE" -B "$PROBE_OUTPUT/arm64" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SDK_NATIVE/build/cmake/ohos.toolchain.cmake" \
  -DOHOS_ARCH=arm64-v8a -DOHOS_STL=c++_shared -DCMAKE_BUILD_TYPE=Debug
cmake --build "$PROBE_OUTPUT/arm64"
cmake -S "$PROBE_SOURCE" -B "$PROBE_OUTPUT/x86_64" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SDK_NATIVE/build/cmake/ohos.toolchain.cmake" \
  -DOHOS_ARCH=x86_64 -DOHOS_STL=c++_shared -DCMAKE_BUILD_TYPE=Debug
cmake --build "$PROBE_OUTPUT/x86_64"
```

两种 ABI 编译和链接成功；SDK `llvm-readelf` 确认 ELF64 的 AArch64 / X86-64。该库只使用 string、atomic、thread；未装入 Stage 应用，未证明排版依赖或 Office 引擎能运行。

SDK 注入的 `--gcc-toolchain` 参数会被当前 Clang 报 unused-command-line-argument；探针仅对这一编译驱动警告取消 Werror，其余源码警告仍作为错误。

## 固定提交的阻断

批准的 LibreOffice 提交为 `6804c10b45d52787c1e865e3ad192d7dfc7d4862`，其 `configure.ac` 的 LF 字节 SHA-256 为 `2da1d3c5933c9f3c5d589477284601322ff088a93cc4f01c8de6f510e577f64d`。

实际执行 `./autogen.sh --host=aarch64-unknown-linux-ohos --build=x86_64-pc-linux-gnu --enable-headless --without-java --disable-gui` 时，上游 `config.sub` 拒绝 `ohos`。尚未实施 OHOS 平台补丁，完整源码/依赖构建未完成。

另一个独立前置条件可重现为：

```bash
python3 check-compiler.py "$LIBREOFFICE_SOURCE" "$SDK_NATIVE"
```

脚本核对批准的 Git HEAD，读取该版本配置中的 Clang 要求，并运行 SDK 的真实目标编译器预处理版本宏。结果为 `15.0.4 < 18`，退出码 2；这是前置条件验证，不是完整 configure 或转换测试。不能删除版本检查或伪造版本来宣布兼容。

下一步版本/工具链提案与修改范围见 [阶段记录](../../docs/OFFICE-ENGINE-TOOLCHAIN-STATUS.md)。

## 上游依据

- [固定源码配置](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/configure.ac)。
- [LibreOfficeKit 官方接口](https://docs.libreoffice.org/libreofficekit.html)。
- [交叉编译说明](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/README.cross)。

SDK 和上游源码/依赖仅留在本地缓存；本 PR 未再分发它们，也未引入运行时字体或模型。
