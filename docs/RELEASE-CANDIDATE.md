# 四条 PDF 路线：Release 候选交付

**2026-10-14 更新：** 下面是 10 月 13 日的历史构建记录。后续修复 Office 资源、加载、桥接、导出句柄和字体回退问题后，四条路线的 Release 真机样例及主应用 DOCX 保存/分享面板已验证。最新包、实际证据与限制见 [Release 真机样例验收](DEVICE-ACCEPTANCE-20261014.md)，旧包不能作为本轮运行证据。

日期：2026-10-13。用户要求完成代码和正式构建，并确认本轮没有真机。随后完成保存、分享和转换内容复查，详见 [交付与内容复查](CONVERSION-DELIVERY-AUDIT.md)。

## 实际改动

四条产品路线 JPEG、PNG、DOCX、PPTX → PDF 现在可在 Debug 和 Release 执行。已移除 ArkTS 的 `BuildProfile.DEBUG` 路线限制和 Native 的 Debug 专用门禁；实际引擎、授权文件、输入格式/保护、资源预算、PDF 校验及产物交付检查继续生效。其余 39 条路线保留源码与定义，仍禁用。

路线记录保留 `experimental`，它表示设备与保真验收尚未完成，**不再表示只能 Debug 执行**。没有填写虚假的 `available` 或 `releaseEvidenceId`。Office 使用真正的 LibreOfficeKit Writer/Impress，目标架构为 OHOS arm64；图片引擎另外支持 x86_64。

Release 转换页默认要求真实文件，不显示示例文件名输入、模拟文件按钮和演示入口。无文件不能启动转换；协调器收到无文件启动请求时打开文件选择器，不创建演示任务。Debug 保留既有演示。转换完成后继续使用受控产物、系统保存和分享流程。

## Office 字体与资源可靠性

默认 `missingFontPolicy=reject`；发现缺失引用字体时停止，提示用户改用已有字体或明确批准替代。转换页新增字体替代勾选项，告知可能改变换行、分页和外观。

只有明确勾选后，授权请求才携带 `approved_fallback` 和 `font_substitution`。调度器拒绝未批准的替代请求；Native 核对策略与获准降级列表是否一致，不允许图片路线携带 Office 选项。LOK 随后使用内置或系统字体处理缺失字体。结果记录缺失引用字体与人工复核要求；没有宣称实际替代字体已经逐字验证，也不会据此授予保真等级。

Office 资源在每个应用进程首次使用时重新核对缓存清单、不可变文件大小和摘要。配置 URL 会由 Native 重写，因此这两个配置文件另检查必需键。缓存缺失或损坏时从随包资源重新安装，不再仅凭 `ready.sha256` 返回成功；Native 还核对标记内容是否匹配当前引擎包。短读写、失败清理和重试继续生效。

Office 仍为串行进程级 LOK 实例。取消和超时在加载/导出边界检查，不能强制中断正在阻塞的 LOK 调用；运行峰值内存和加载器命名空间仍需在设备测量。

## 图片与构建

JPEG 的已实现转换与交付流程保留。PNG 现在按 `pHYs` 的实际像素每米信息计算 PDF 页面尺寸；没有物理分辨率时使用 96 DPI。已验证 300×300 与 300×150 DPI，比较文件实际存储的整数精度，而非保存时传入的近似 DPI。透明度仍使用 PDF `/SMask`。

开发电脑首次 Release 构建遇到依赖下载 TLS 失败，已使用本地固定源码归档解决。`third_party/archives` 保存 libpng、zlib、miniz、tinyxml2 的原始归档；CMake 优先读取这些文件并继续核对原 SHA-256。没有关闭 TLS 检查，也没有改变版本。应用运行时仍无网络下载和 INTERNET 权限。

## 构建与证据

- 实际鸿蒙 SDK Release 编译、签名与打包通过；生成的 `BuildProfile` 为 `BUILD_MODE_NAME='release'`、`DEBUG=false`。
- Native CTest：25/25，包含新增的字体批准/矛盾策略拒绝检查。
- 核心文档检查：34 项。PNG 是实际 Native 执行及独立 pypdf/Poppler 检查；Office 此处验证输入包、正文摘要和内嵌图片解码，不运行 Office 导出。
- 缓存/解析生命周期：22 项，真实 ArkTS 配合 Node IO、明确模拟的解压与 PDF SDK，包含缓存恢复、文字/图片/页数检查及 PixelMap 释放。
- Release 流程检查：真实 ArkTS 注册、预检查、桥接、调度器及协调器，配合模拟 Native；四条路线可调度，失败 PDF 释放、缺失引擎和未批准字体替代仍拒绝。
- 保存分享 13 项、交付生命周期 3 项通过；JPEG 实际独立解析与渲染 29 项通过。输入授权、队列、语言、配置完整性、完成/保真声明等相关宿主回归通过。
- 最终 HAP 静态检查：235 个 Office 库、3271 个资源文件、LOK 导出符号、UNO 路径补丁、直接依赖、资源摘要及静态编解码符号隔离通过。

候选包：`entry/build/default/outputs/default/entry-release-signed.hap`，**392,680,329 字节，约 393 MB**。

SHA-256：`7fc3f884ae74b4b7e1ff673c2f6b95549fc494af9317ae618ef00b7d876daed3`。

报告：`tests/generated/release-routes-host-report.json`、`core-routes-release-hap-validation.json`、`core-document-engines.json`、`bundled-runtime-regression.json`；本次复查构建日志在 `tmp/core-engines/delivery-release-build.log`。

本轮没有安装、启动、运行 hdc 或真实设备转换。签名使用当前工程已有配置；此处的 Release 候选构建不等于应用市场已经审核通过。

## 上线验收仍缺的证据

必须用这版候选包在目标手机实际验证 Office 初始化和 DOCX/PPTX 导出、PNG/PDFKit 解析、首次断网资源准备、保存后独立打开和分享。同时核对真实文档页数、页面尺寸、正文、关键数值、表格、图片和外观，测量时间、内存与取消行为。

当前已完成代码与 Release 执行入口，不能把电脑端编译、模拟 SDK 或静态包检查解释为这些设备项目已经通过。输入范围和原始接入记录见 [四条 PDF 路线](CORE-PDF-ROUTES.md)；旧 DOC/PPT、渐进式/CMYK JPEG、PNG 动画/16 位/特殊元数据、Office 外链/宏/OLE 等仍未开放。
