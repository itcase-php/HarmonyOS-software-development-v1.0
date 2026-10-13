# 四条单向 PDF 路线：代码与验证记录

**2026-10-13 更新：四条路线已支持 Release 执行，完成真实文件入口、字体替代批准、缓存恢复及 PNG 分辨率处理。随后补齐保存/分享回读核验、交付期间产物保留及 Office 文字/图片/字体检查。约 393 MB 的签名 Release 候选包已构建并检查，设备验收仍待执行。最新结果见 [交付与内容复查](CONVERSION-DELIVERY-AUDIT.md)和 [Release 候选交付](RELEASE-CANDIDATE.md)，下面保留 2026-10-11 接入阶段记录。**

日期：2026-10-11。工程：`D:/HarmonyOS/harmonyOS`。用户批准收敛为 JPEG、PNG、DOCX、PPTX → PDF；本轮没有连接或调用真机。

## 当前结果

| 路线 | 主应用实现与随包引擎 | 当前证据 |
| --- | --- | --- |
| JPEG → PDF | 保留既有 libjpeg-turbo 与 JPEG/PDF 核心，保留 EXIF/ICC、保存和分享流程 | 本轮主机回归 29 项；此前设备证据保留，新包未进行设备复验 |
| PNG → PDF | 静态编入 libpng 1.6.59、zlib 1.3.2；实际解码并写入 RGB 与透明度 PDF 流 | 6 种图像模式实际执行、pypdf 解码像素对比、Poppler 渲染及目视检查通过；设备待验收 |
| DOCX → PDF | 真实 `OfficeConverter` 调用 LibreOfficeKit 26.2.6.2 Writer 导入及 PDF 导出；arm64 库与资源内置 | 目标构建、主应用 SDK 编译、包内 ELF/接口/依赖及资源完整性检查通过；引擎初始化、实际 DOCX 导出与版式待设备验收 |
| PPTX → PDF | 同一内置引擎调用 Impress 导入及 PDF 导出 | 代码、构建与打包检查通过；实际 PPTX 导出与版式待设备验收 |

四条路线为 `experimental`，仅 Debug 允许执行。Release 仍关闭，没有填写发布验收证据。Office 仅支持 OHOS arm64；x86_64 构建保留图片引擎，明确返回 Office ABI 不支持。不能用签名包构建成功代替真机转换成功。

## 范围收敛与原代码保留

`shared/format-registry/product-scope.json` 是本阶段唯一入口范围，生成 ArkTS 与 C++ 同源名单。格式浏览和功能指南仅显示 JPEG、PNG、DOCX、PPTX、PDF，其中 PDF 仅作为输出；转换源列表只有四种输入。规划器、ArkTS 执行入口和 Native 路线门禁均拒绝范围外路线。

原始 18 种格式、43 条路线定义仍保留。其余 39 条路线从入口中过滤、不能执行；反向 PDF/Office、媒体、OCR 等原代码和占位类保留，未删除。JSON 不支持注释，因此使用显式范围文件和代码注释禁用，避免破坏配置解析。没有将 unsupported 或 planned 路线伪装为 available。

## 真实处理与完成判定

真实文件仍经过系统 Picker、授权副本、大小与 SHA-256 校验、Native 深层探测及受控工作区。Native 根据四条路线调用 image 或 office 转换器，并提交不透明产物引用；既有 PDF 保存、分享与产物释放复用。

PNG 使用 libpng 解码静态像素，zlib 压缩 RGB；透明像素使用 PDF `/SMask`，不静默抹去透明度。页面以 96 DPI 计算，单图单页。Office 使用 ZIP/OOXML 深层检查，再由 LOK 加载文档、判断 Writer/Impress 类型并执行 `saveAs(..., "pdf", ...)`，没有把文本或页面截图包装成 Office 转换成功。

JPEG 保留已有结构与内容校验。PNG/Office 先通过 Native PDF 包络校验，再复制受控产物，由系统 PDFKit 独立加载、检查加密与页数并遍历页面文字/图形对象；随后才允许任务显示完成。任何失败都会释放产物，不显示保存/分享资格。PDFKit 调用已通过实际 SDK 编译，本轮只在模拟 SDK 中验证异常清理，尚未在设备运行。

完成结果必须恰有一个有效目标主产物，字节数为正，SHA-256 和不透明引用合法。拒绝空文件、错误格式、报告冒充主产物、多个输出、无效摘要或引用及失败校验。声称已达到的保真等级还必须有实际指标和证据。Office 只报告实际输出页数，并保留人工复核标志；目前不会声称达到请求中的保真等级。

## 引擎与离线资源

固定上游提交：`ad5cf9fd4989cacf0bca866ebefc0ec8926cb0b2`，标签 `libreoffice-26.2.6.2`。OHOS 移植补丁、工具链及完整构建记录见 [Office 移植记录](OFFICE-26.2-PORT.md)和 [复现入口](../prototypes/office-harmony/README.md)。

`tools/package-office-main.py` 将已构建的 arm64 Stage 运行库、LOKit 头文件和离线资源复制到主应用；`shared/engines/office-bundle.json` 固定各文件摘要。CMake 在编译 arm64 可执行 Office 能力之前核对全部 235 个库和资源 ZIP，缺失或不匹配直接构建失败。大体积二进制留在本机、未纳入 Git，其他机器必须先按复现入口构建或提供匹配的运行库。

首次 Office 任务从包内解压资源，核对清单、ZIP 和 3271 个资源文件的大小及 SHA-256，然后安装到应用缓存。包含配置、过滤器、DejaVu Sans 字体与许可文件；不需要运行时下载，没有声明 INTERNET 权限。资源准备失败清理暂存目录并允许重试；同时调用共享一次准备流程。配置写入支持短写入。

最终主应用签名 Debug HAP 为 **394,807,861 字节，约 395 MB**；Office 资源解压后为 163,012,146 字节，首次准备要求缓存至少 400 MiB 可用空间。当前优先保留依赖以便验证，尚未做经过转换验收的包体裁剪。第三方引擎及资源按其各自许可文件提供，项目源码的 MIT 许可不替代第三方许可。

## 明确的输入边界

- JPEG 保留既有受限 Baseline、EXIF/ICC 能力；渐进式、CMYK 和不支持的附加段仍按既有策略拒绝。
- PNG 支持静态不超过 8 位的灰度、RGB、RGBA、灰度透明、调色板及 1 位图。本阶段拒绝 16 位、APNG、ICC、自定义色彩/伽马、EXIF 等尚未实现的处理，不宣称任意 PNG 都可转换。
- Word/PPT 指 **DOCX/PPTX**，不包括旧 DOC/PPT。拒绝加密、签名、文档/写保护、DTD、外部关系、宏、ActiveX、OLE 嵌入和 SVG 等未验收特征，并限制 ZIP 展开量、XML 大小/深度及输入资源预算。
- Office 要求引用字体在随包或系统字体中有同名字族；缺失返回明确字体错误，不静默替换。扫描样式/主题也可能找到未实际使用的字体并拒绝文件；没有实现字体导入或批准替代流程。手机可用字体和复杂对象均待实际验收。
- Office 采用进程级单实例、串行 LOK 调用。取消和超时在加载/导出前后检查；不能中断正在阻塞的 LOK 调用，也没有证明其运行峰值受硬内存上限限制。不得根据输入预算检查宣称这些设备约束已完成。

## 本轮验证

| 检查 | 结果和证据边界 |
| --- | --- |
| Native CTest | 25/25；主机契约、JPEG 运行时与桥接等回归 |
| 核心文档检查 | 24 项；PNG 实际转换/独立 PDF 检查，Office 输入包检查，未执行 Office 引擎 |
| 资源与 PDF 生命周期 | 12 项；真实 ArkTS、Node 文件系统、明确模拟的解压/PDF SDK；校验、失败清理、短读写及重试 |
| 完成与保真声明门禁 | 9 项；真实 ArkTS 配合模拟 Native 返回；8 个异常结果均拒绝 |
| UI 范围、队列、授权输入、交付、配置、语言和保真演示回归 | 相关宿主检查通过，不能代替实际系统 Picker/分享/设备测试 |
| 主应用构建与 HAP 检查 | 实际 SDK 编译及签名通过；235 个 Office 库、资源摘要、LOK 导出、UNO 路径补丁和直接依赖检查通过；加载器命名空间未运行验证 |

主要报告：`tests/generated/core-document-engines.json`、`bundled-runtime-regression.json`、`capability-guards-regression.json`、`core-routes-hap-validation.json`；本轮 JPEG 回归保存在 `tmp/core-engines/jpeg-regression.json`，没有覆盖旧设备验收记录。

在已配齐工具链及引擎的电脑上，可执行：

```powershell
python tools/package-office-main.py --stage tmp/offline-engines/office-stage-probe/entry
node tools/generate-registry.cjs
node tests/check-core-scope.cjs
node tests/check-bundled-runtime.cjs
node tests/check-capability-guards.cjs
python tests/check-core-document-engines.py tmp/core-engines/native-build/hdm_document_cli.exe
python tests/check-core-routes-hap.py
```

主应用使用 DevEco Studio 的 Debug 构建；原生主机测试需要单独以 MSVC 配置 `entry/src/main/cpp/tests`，详见该目录 CMake。FetchContent 依赖下载只发生在开发构建阶段，可使用已校验的本地源目录；运行时不访问网络。

## 设备验收待办

本轮未执行安装、启动或 hdc。后续必须实际验证：新包加载引擎、首次断网资源准备、PNG/DOCX/PPTX 实际转换、PDFKit 解析、逐页尺寸/文本/关键数值/表格/图片/外观核对，以及保存后独立打开与分享。还需测量时间、内存和取消行为。通过这些项目后才可以填写对应设备验收结果或评估 Release 开放。
