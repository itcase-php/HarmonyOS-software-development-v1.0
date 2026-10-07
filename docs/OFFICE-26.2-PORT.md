# LibreOffice 26.2.6.2 OHOS 移植记录

日期：2026-10-07。用户已批准更换固定版本，且本轮没有手机，先推进构建和代码验证。最终目标仍为真实 DOCX/PPTX 在鸿蒙 arm64 手机上首次断网导出 PDF；本记录不能替代该验收。

## 源码与工具链

- 官方仓库：`https://github.com/LibreOffice/core.git`。
- 标签：`libreoffice-26.2.6.2`；标签对象 `bb82c515eaebfe3b1f966445c446366c2b7da1bb`；提交 `ad5cf9fd4989cacf0bca866ebefc0ec8926cb0b2`。
- 原始 `configure.ac` SHA-256：`f9c661dd95afb8c11960f0658d96d5b20dec8f48125bb000d6e3b797b7018fa5`。
- 官方 Linux Native SDK：API26 / 26.0.0.105；Clang15.0.4；实际目标 `aarch64-linux-ohos`。本版本的 Clang>=12 前置检查通过。
- 上游完整源码和依赖保留在 WSL 缓存 `/home/tx/.cache/hdm-office/26.2.6.2`，旧源码未删除。项目只保存源码锁定、补丁和复现脚本。

## 已完成与验证边界

原始 `config.sub` 实际拒绝 `linux-ohos`。新增局部补丁注册目标、选择 POSIX/musl 构建规则并允许无 X11 的 headless 配置；使用官方 OHOS compiler/sysroot/libc++，没有替换为 Android 或桌面 Linux 二进制。

目标编译中，libeot 的旧 `config.sub` 同样拒绝 OHOS，已通过上游现有 helper 复用根目录配置脚本。SDK libc++ 缺少 `make_unique_for_overwrite`，已将 SAL 数值转换的两处数组分配改成等价的 `unique_ptr::reset(new T[n])`，保留不初始化语义。补丁后的真实主机 SAL 库通过长窄字符/UTF-16 数值的值、状态和解析位置回归；完整上游 CppUnit 套件因 cross-toolset 缺少测试包而未执行。

修复后，arm64 目标与宿主构建工具的 configure 均成功。已隔离 target pkg-config，目标 fontconfig/freetype 等依赖从源码构建。WSL 安装的 fontconfig/freetype/expat 开发包及 xsltproc 只供宿主构建工具使用。configure 成功并不证明目标库已构建、可加载或能转换。

构建关闭素材库生成步骤，避免为 `gengal` 构建额外的主机界面依赖。采用普通共享库模式；LibreOfficeKit 官方加载器支持 `libsofficeapp.so`，不要求合并库。保留核心依赖 curl 与从源码构建的 OpenSSL，关闭 WebDAV/CMIS 连接器；不能因此宣称文档外链或联网行为已完成安全验证。

本次独立构建关闭 PDF 导入，避免为 Word/PPT→PDF 的初步验证引入 Poppler ranges 兼容工作；PDF 导出保留。含内嵌 PDF 的文件尚无保真保证。fontconfig 配置脚本的 snprintf 宏缺失，且 `va_copy` 检测会运行目标程序，已加入配置生成步骤及基于 SDK C99 API 的交叉缓存。SDK 已编译、链接专用 C99 探针，但设备运行结果仍未知；不能把缓存值当成设备测试通过。

已产出 SAL、ICU、libxml2 等基础目标库。2026-10-07 05:16 UTC 的 18 库快照均为 ELF64/AArch64，直接版本依赖未发现 glibc；这不是完整依赖闭包或可运行引擎的证明。

OHOS SDK 不提供桌面 GTK/gettext 的两个绑定函数，已局部排除这段互操作调用，保留 Boost 消息加载。默认纸张发现也跳过桌面 `paperconf` 和 glibc `_NL_PAPER_*` 查询，沿用现有地区回退；不改变文档声明的页面尺寸。这两项仍须结合目标运行验证。

SDK libc++ 还缺少 `stringstream::view()`。LOK 选择对象 JSON 的两处读取改用 `str()` 获取相同内容，增加一次短字符串复制。

完整构建中的 Calc 字符区间表使用 SDK 缺少的 `std::ranges::all_of/is_sorted`。已改为标准迭代器版本，保留原条件及编译期断言，不开放新的应用路线。

新增独立 [LibreOfficeKit 验证程序](../prototypes/office-harmony/lok-probe/main.cpp)，执行真实初始化、加载、PDF 导出和资源释放。官方 SDK arm64 编译和链接成功；ELF64/AArch64，动态依赖为 `libc++_shared.so`、`libc.so`。它只在运行时加载引擎，因此这个结果不是引擎构建成功。主机侧参数错误返回 64、引擎目录不存在返回 2，并确认没有创建 PDF；没有运行真实转换。

完整目标构建进行中。现有五页、18 种格式、43 条路线、JPEG Debug 白名单、Native 协议及 Office 工厂没有修改。Office 路线仍不可用。

## 待完成验收

1. 完整构建 Writer/Impress/PDF 输出所需目标库，核对 ELF ABI 和全部动态依赖，定位并修复后续源代码兼容问题。
2. 整理 UNO 注册、过滤器、配置及授权字体资源，构建不申请 INTERNET 的最小 Stage 验证应用。
3. 在设备上加载、初始化、分别处理真实 DOCX/PPTX、导出 PDF、释放资源；记录包体、耗时、峰值内存和临时空间。
4. 对参考 PDF 比较页数、页面尺寸、文本、关键数值、表格、图片和逐页外观。确认缺失字体及不支持特征不会静默降级。
5. 通过后接入正式 OfficeConverter、输入探测、调度与通用 PDF 校验，再分别开放 Debug 路线。Release 和正式保真声明另据验收证据审核。

LibreOffice 及本地修改需遵循上游 MPL-2.0 等许可；项目的 MIT 许可证不能覆盖第三方引擎。当前没有向应用包再分发该引擎、字体或上游依赖。
