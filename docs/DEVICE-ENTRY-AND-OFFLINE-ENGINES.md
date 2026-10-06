# 真机入口修复与离线引擎验证

日期：2026-10-06。按用户批准的六方向计划推进。完整 Office 转换、可编辑重建及六方向保存/分享尚未完成；现有 43 条规划路线没有升级为 available。

## 已实现与需要审阅的既有功能变化

| 修改 | 行为与依据 |
| --- | --- |
| LanguageManager | 显式 args 优先，仅剥离明确的 app.string.* 名称；保留普通首参数、0、空字符串和顺序。名称/ID 分别用官方 getStringByNameSync/getStringSync。已知键失败时双语目录回退，未知 ID 显示诊断标记，文件名直接通过。 |
| FormatBrowser | 七处带参数调用改成资源键＋独立数组。AST 检查全应用不再有带格式参数的嵌套 $r()。其他无参数调用保留。 |
| ConverterCoordinator | 确认、Native 授权和入队前直接查询能力，传播加载/协议错误，不用首页演示回退。五秒超时、请求代次、离页和确认前后快照核对防止迟到结果/旧选择提交。 |
| 重试与错误提示 | 失败保留导入文件，重试重新预检查。中英文分别说明模块、协议、引擎、路线、超时、选择改变、Picker、导入、探测问题。 |
| 诊断 | 官方 hilog 格式记录模块、阶段、路线、错误码、traceId；不记录正文、文件名、URI、参数内容或签名信息。 |
| 测试基线 | 历史 baseline 文件保留；input-management/fidelity 另行固定此前批准的 04e6886 交付协议摘要。语言检查保护已提交签名配置，用户的本地签名配置排除本次提交。 |

保留五页、18 种格式、43 条原路线、演示队列、语言生命周期、保真/保护策略及现有资源限制。主工程 NativeBridge、NativeProtocol、C++、共享矩阵、权限和保存分享服务未改。OCR/PDFKit 在独立测试 HAP 中验证，不接主引擎工厂或能力声明。

## 两个问题的证据

`%s` 是未替换的模板，不是文件编码乱码。手机 Hypium 观察到 $r() 的 params 有一个参数，首项没有名称前缀；旧 slice(1) 因此丢失实际值。新解析同时覆盖有前缀的预览形态，不猜测普通字符串的资源名，不返回空白掩盖未知资源。

截图中的真实 DOCX 已进入任务流程，不能据此认定 Picker 失败。本次通过系统 Picker 导入自建 DOCX 后，提交前明确提示“此路线所需的离线引擎尚未接入。已保留文件，请更换路线或等待引擎验证完成。”没有创建失败任务、弹出转换确认或注册授权会话。取消 Picker 也正常返回。

正式服务仍由 EntryAbility 初始化；保留 canIUse，分别记录系统能力、Picker 构造与选择。未添加 READ_MEDIA，继续用用户选择 URI、受控分块副本、大小限制、SHA-256 和句柄释放。

## 验证记录

| 层次 | 结果 | 边界 |
| --- | --- | --- |
| 新宿主回归 | 11 项通过 | SDK 参数传递、双语回退、配置改变、超时、输入保留和迟到结果；不是设备执行 |
| 其他宿主 | 交互15、架构21、输入35、保真13、语言8、重构12、Hypium源代码61项通过 | 保真仍为演示逻辑 |
| Native 主机 | MSVC/Ninja CTest 22/22 | 不等于设备 Office 转换 |
| Hvigor | 主应用、ohosTest、独立原型签名 debug HAP 成功，两个 ABI 编译 | 本地签名资料不上传 |
| 手机 Hypium | 63/63，包括实际 ResourceManager 新用例 | 既有宿主61项＋模板1项＋新资源1项 |
| 手机 ArkUI | 中文→英文→中文；详情 ID/扩展名/MIME/操作正确；真实导入、取消、预检查通过 | 未验收重启持久化、完整读屏、全部文件提供者 |
| OCR | Tesseract/Leptonica 双 ABI 鸿蒙编译；arm64 手机中英文固定图片识别成功 | x86_64 未执行；无表格/复杂版式重建 |
| PDFKit | 手机两页解析、文字对象提取、文字页/扫描页渲染及扫描页→中英文OCR成功 | 无 Office 加载、排版或写出 |

设备 const.ohos.apiversion 返回24，编译使用本工程 API26 SDK；不能把当前结果扩展为所有 API26 真机或最低兼容验收。原型没有 INTERNET 权限，模型和样例随包提供；没有手动切换整机飞行模式，不声称六方向首次断网验收完成。

脱敏结果在 tests/generated/device-entry-host-check-report.json、device-entry-device-validation.json、ocr-harmony-feasibility.json。原始 UI 文件列表、日志、HAP、依赖源码和签名配置均留在 tmp。

固定原始 PGM 识别约202ms、进程峰值120784KiB；PDF扫描页渲染后的识别约212ms、进程峰值151488KiB，两者引擎平均置信度92。英文结果为 Harmony offline OCR 12345，中文为“鸿 蒙 离 线 文档 转换 67890”，存在分词空格。耗时只统计OCR worker，不含PDF解析、渲染或模型复制；进程峰值包含ArkUI/VM，不是Native预算测量。没有测量完整文档/300页的耗时、临时空间或字体包。

同一进程在PDF测试后重复PGM识别也成功，约209ms，生命周期峰值升至172976KiB。该值是累计高水位，不是此次引擎增量分配；不能用首次单样例峰值证明192MiB生产预算满足，需要后续长期运行、GC与引擎内存测量。

测试期间直接从data/local/tmp执行CLI被系统拒绝，改用正常签名Stage HAP，未绕过系统策略。新Hypium最初使用主模块上下文导致测试模块资源ID不匹配，改为真实Stage上下文创建entry_test资源管理器后63项通过。扫描OCR初次连接失败于重复创建已存在缓存目录，原型增加存在检查后实际连接成功。这些失败没有通过开放主路线或改写发布证据解决。

## 引擎阻断与后续提案

LibreOffice 固定审阅提交为 6804c10b45d52787c1e865e3ad192d7dfc7d4862。configure.ac 没有 OHOS 操作系统分支，默认在1306/5914行拒绝未知平台；其 SHA-256 为 2da1d3c5933c9f3c5d589477284601322ff088a93cc4f01c8de6f510e577f64d。官方交叉编译说明也没有鸿蒙目标。

这是**源码平台审阅，未完成 LibreOffice 全源码目标编译，也不证明无法移植**。需要专门的 OHOS 平台、headless 排版、UNO/依赖资源、字体度量和线程归属适配；不能复用 Android/Linux 二进制。下一验收点应为一个合法 DOCX 和 PPTX 的离线 PDF 输出及资源测量。目前没有目标 Office 库，DOCX↔PDF、PPTX↔PDF、DOCX↔PPTX 六方向均未开放。

API26 官方 PDFKit 已提供文字/字符坐标、图像对象、页面尺寸、旋转和 PixelMap 渲染；独立原型优先验证它。它不是 Office 排版引擎，不会自动生成可编辑 DOCX/PPTX。原型同步 pdfService 只处理小样例；正式接入先验证线程支持、异步调度、取消、坐标映射和资源上限，不能搬到主 UI 线程处理大文档。

OCR 固定版本、摘要和参数在 prototypes/ocr-harmony/dependencies.json。Leptonica 关闭通用图像 codecs，只处理固定 PGM/原始栅格；Tesseract 为 LSTM＋内置 eng/chi_sim，不运行时下载。识别文本有中文分词空格；引擎置信度不当成文档准确率。扫描流程仍需旋转/裁剪、区域去重、混合页、表格及低置信复核，必要 OOXML 写出和关系/ZIP 校验、字体批准替代、真实保真报告均未实现。

下一步优先验证官方 PDFKit→OCR→受控 IR，再按保外观/可编辑模式新增独立路线，不重定义43条原路线。LibreOffice 移植成功并实测后才接入正式白名单。若移植或保真失败，再向离线 SDK 厂商索取六方向、中文OCR、编辑结构、字体、取消、双ABI及再分发的接口和设备验证条件。Foxit 有官方鸿蒙 PDF SDK 资料，但不能据此认为支持完整六方向 Office 转换。

购买 SDK、接入云服务、扩大100MiB/300页/192MiB/180秒限制、改变保真/字体承诺或发布门禁，都先提交具体差异和测量给用户审核。本轮没有购买、接云、合并或伪造发布证据。

## 官方依据

- [华为 Picker](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)。
- [官方 ResourceManager](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-localization-kit/js-apis-resource-manager.md)，同时核对 API26 SDK 和设备行为。
- [官方 HiLog](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-performance-analysis-kit/js-apis-hilog.md)、[NAPI 异步模板](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/napi/use-napi-asynchronous-task.md)。
- [华为 PDFKit](https://developer.huawei.com/consumer/cn/sdk/pdf-kit/)、[官方渲染样例](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/pdf-get-img-V14)。具体同步 pdfService 签名使用 API26 SDK @hms.officeservice.pdfservice.d.ts，不混用 PdfController 异步签名。
- [LibreOfficeKit](https://docs.libreoffice.org/libreofficekit.html)、[固定 configure.ac](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/configure.ac)、[交叉编译说明](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/README.cross)。
- [Tesseract 构建](https://tesseract-ocr.github.io/tessdoc/Compiling.html)、[Leptonica](https://github.com/DanBloomberg/leptonica/tree/1.85.0)、[固定模型](https://github.com/tesseract-ocr/tessdata_fast/tree/87416418657359cb625c412a48b6e1d6d41c29bd)。
- [Foxit 鸿蒙 PDF SDK 官方指南](https://developers.foxitsoftware.cn/SDKdoc/Foxit_PDF_SDK_HarmoryOS_DeveloperGuide_CN.pdf)：候选线索，尚未引入或购买，完整六方向能力未确认。
