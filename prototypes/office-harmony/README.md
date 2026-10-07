# Office 鸿蒙工具链前置验证

2026-10-07：用户已批准采用 LibreOffice **26.2.6.2** 继续移植。新源码锁定与 OHOS 配置补丁见下节；后面的旧提交阻断记录保留用于对照。

本目录用于 Office 移植验证，不提供已验收的 OfficeConverter，不发布转换能力。DOCX/PPTX 真机转换尚未执行。

## 26.2.6.2 移植入口

- 固定源码由 [upstream.json](upstream.json) 指定：标签 `libreoffice-26.2.6.2`，提交 `ad5cf9fd4989cacf0bca866ebefc0ec8926cb0b2`，同时记录原始 `configure.ac` 的 SHA-256。
- `check-compiler.py` 检查 Git HEAD 和原始配置摘要，再运行 SDK 真实目标编译器。该版本要求 Clang >=12，官方 API26 的 Clang15.0.4 已通过此项检查。
- [配置补丁](patches/0001-ohos-configure.patch) 注册 `linux-ohos`，使用现有 POSIX/musl Linux gbuild 规则并标注 OHOS 平台，允许无 X11 的 headless 配置。该补丁是移植起点，不是完整平台支持证明。
- [libeot 补丁](patches/0002-libeot-config-sub.patch) 让嵌入字体依赖复用已支持 OHOS 的平台识别脚本；[SAL 补丁](patches/0003-sal-array-allocation.patch) 用等价的不初始化数组分配替代 SDK libc++ 缺少的 `make_unique_for_overwrite`。
- [fontconfig 补丁](patches/0004-fontconfig-cross-configure.patch) 在 OHOS 构建前重新生成含 snprintf 宏的配置脚本，并为 SDK 的 C99 `va_copy` API 设置交叉配置缓存。配置入口先编译、链接 [C99 探针](fontconfig-c99-probe.c)；设备执行仍待完成。
- [gettext 补丁](patches/0005-ohos-gettext-interop.patch) 排除 OHOS SDK 不提供的桌面 GTK/gettext 绑定调用，保留 Boost 消息加载；[默认纸张补丁](patches/0006-ohos-default-paper.patch) 使用已有的地区回退，跳过桌面 `paperconf` 和 glibc 查询，文件声明的页面尺寸不变。
- [字符串流补丁](patches/0007-stream-buffer-access.patch) 用 `str()` 替代 SDK libc++ 缺少的 `stringstream::view()`，保持 LOK 选择对象 JSON 的内容。
- [编译期算法补丁](patches/0008-constexpr-algorithms.patch) 用标准迭代器算法替代 SDK 未提供的 ranges 算法，保留 Calc 字符区间表的两条编译期校验。
- [configure-ohos.sh](configure-ohos.sh) 校验源码、应用补丁，隔离目标 pkg-config 路径，使用官方 `aarch64-linux-ohos`、sysroot 和 libc++。宿主构建工具使用单独的 build 配置，不能作为鸿蒙运行库。

在 WSL 中使用独立、未修改的上游 checkout：

```bash
git clone --depth 1 --branch libreoffice-26.2.6.2 --single-branch \
  https://github.com/LibreOffice/core.git "$OFFICE_SOURCE"
bash prototypes/office-harmony/configure-ohos.sh \
  "$OFFICE_SOURCE" "$SDK_NATIVE" "$OFFICE_BUILD"
make -C "$OFFICE_BUILD" -j4 build
```

三个变量由调用者设置为绝对路径；源码与输出应放在 WSL 文件系统，避免 Windows 盘上的大规模小文件 I/O。主机还需要 `autoconf-archive`、`autopoint` 来生成 fontconfig 的配置脚本。第三方依赖由固定上游下载清单校验 SHA-256。没有打包字体；字体授权、随包资源及缺失字体策略仍需完成。构建关闭 WebDAV/CMIS 连接器、Java/Python、GUI、数据库与 PDF 导入功能，保留 Writer/Impress 和 PDF 输出；含内嵌 PDF 的复杂 Office 文件需要另行验收。不据此宣称文档外链已通过安全验收。

本轮详细状态见 [26.2.6.2 移植记录](../../docs/OFFICE-26.2-PORT.md)。

构建结束后，静态检查目标 ELF 架构、版本依赖以及 `DT_NEEDED` 文件名：

```bash
python3 prototypes/office-harmony/check-target-elf.py \
  "$OFFICE_BUILD" "$SDK_NATIVE" "$OFFICE_BUILD/target-elf-validation.json"
```

缺少主引擎、Writer、Impress、PDF 导出库、LOK 初始化导出符号或依赖文件时返回失败。SDK 中存在的运行库仍需按许可打包；该检查不验证目标动态加载器命名空间、运行时符号解析或转换结果。

修改 SAL 分配方式后，可在已配置的 WSL 交叉构建目录执行主机回归：

```bash
bash prototypes/office-harmony/check-sal-math.sh "$OFFICE_SOURCE" "$OFFICE_BUILD"
```

该检查重新构建主机 SAL 库，调用其中的真实数值转换函数，验证超过 256 字符的窄字符/UTF-16 输入保留数值、状态和解析结束位置。本轮通过；它不是鸿蒙运行测试。完整上游 CppUnit 套件未执行，当前 cross-toolset 不包含所需的 `test_unittest` 测试包。

## LibreOfficeKit 调用验证程序

[lok-probe](lok-probe/main.cpp) 是独立的命令行验证程序，不接入正式应用。它通过上游 `lok_init_2` 加载真实库，用 `documentLoadWithOptions` 加载本地样本并明确禁用宏，再用 `saveAs(..., "pdf", ...)` 导出和释放资源。没有引擎、初始化失败、加载失败或导出失败均返回非零状态，不生成替代内容。

```bash
cmake -S prototypes/office-harmony/lok-probe -B "$LOK_PROBE_BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SDK_NATIVE/build/cmake/ohos.toolchain.cmake" \
  -DOHOS_ARCH=arm64-v8a -DOHOS_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Debug -DOFFICE_SOURCE="$OFFICE_SOURCE"
cmake --build "$LOK_PROBE_BUILD"
"$SDK_NATIVE/llvm/bin/llvm-readelf" -h -d "$LOK_PROBE_BUILD/hdm_office_lok_probe"
```

本轮已编译、链接该调用端，ELF 为 AArch64，依赖 `libc++_shared.so` 和 `libc.so`。它动态加载 Office 库，因此编译成功不代表引擎库已构建或转换可用。主机侧仅验证参数错误（64）与不存在的引擎目录（2），确认没有输出 PDF。

在 Linux 主机上重现这两条失败路径：

```bash
bash prototypes/office-harmony/check-lok-host.sh "$OFFICE_SOURCE" "$OFFICE_BUILD/lok-host-check"
```

引擎和资源准备好后，在目标设备上使用独立配置目录、可信 DOCX/PPTX 样本和全新的输出路径执行：

```text
hdm_office_lok_probe /absolute/program file:///profile file:///input.docx file:///new-output.pdf
```

程序返回 0 仅表示引擎报告导出成功；仍须独立核对 PDF 内容和版式。文件 URI 限制不等于文档外链防护，不应用此探针处理不可信文件；正式应用的权限、字体预检、预算与安全策略仍待接入。该命令行验证程序也不能替代 Stage 应用沙箱内的运行验证。

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

此前批准的 LibreOffice 提交为 `6804c10b45d52787c1e865e3ad192d7dfc7d4862`，其 `configure.ac` 的 LF 字节 SHA-256 为 `2da1d3c5933c9f3c5d589477284601322ff088a93cc4f01c8de6f510e577f64d`。以下为当时的历史结果，当前检查脚本已跟随 `upstream.json` 切换至新版本。

实际执行 `./autogen.sh --host=aarch64-unknown-linux-ohos --build=x86_64-pc-linux-gnu --enable-headless --without-java --disable-gui` 时，上游 `config.sub` 拒绝 `ohos`。尚未实施 OHOS 平台补丁，完整源码/依赖构建未完成。

当时另一项独立前置检查命令为：

```bash
python3 check-compiler.py "$LIBREOFFICE_SOURCE" "$SDK_NATIVE"
```

旧脚本核对当时批准的 Git HEAD，读取配置中的 Clang 要求，并运行 SDK 的真实目标编译器预处理版本宏。结果为 `15.0.4 < 18`，退出码 2；这是前置条件验证，不是完整 configure 或转换测试。不能删除版本检查或伪造版本来宣布兼容。

下一步版本/工具链提案与修改范围见 [阶段记录](../../docs/OFFICE-ENGINE-TOOLCHAIN-STATUS.md)。

## 上游依据

- [固定源码配置](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/configure.ac)。
- [LibreOfficeKit 官方接口](https://docs.libreoffice.org/libreofficekit.html)。
- [交叉编译说明](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/README.cross)。

SDK 和上游源码/依赖仅留在本地缓存；本 PR 未再分发它们，也未引入运行时字体或模型。
