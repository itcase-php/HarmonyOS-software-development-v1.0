# 功能声明与实际执行代码检查

2026-10-11 修复增量：主应用已实施目标主产物、数量、正字节数、摘要、不透明引用和无证据保真等级的拒绝检查；9 项模拟异常/对照回归通过。PNG/Office 完成前增加独立 PDFKit 解析和页面遍历，异常产物释放。反向 Office 路线保留但已从当前范围禁用。四条单向路线的真实引擎、包内资源及验证边界见 [当前阶段](CORE-PDF-ROUTES.md)。下文是修复前审计证据，未删除。

日期：2026-10-07。检查目录：`D:/HarmonyOS/harmonyOS`。本轮检查、构建和复现没有调用真机，也没有修改应用功能或路线开关。本文区分异常返回复现、源码/API 合约发现和已通过的主机检查，不能据此声称当前手机发生了相同故障。

## 1. P1：异常产物仍可显示转换完成

位置：`entry/src/main/ets/services/NativeBridge.ets:156`、`entry/src/main/ets/viewmodel/TaskStore.ets:318`、`TaskStore.ets:372`。

桥接只要求成功结果的 `validation.state === 'passed'` 和输出数组非空；任务存储随后标记完成。没有在显示完成前核对主产物是否符合目标格式，以及字节数、摘要、产物引用是否有效。

使用真实 ArkTS 桥接、调度及任务存储，注入模拟 Native 返回，复现如下：

| 模拟返回 | 显示状态 | 保存/分享按钮资格 | 随后的导出参数检查 |
| --- | --- | --- | --- |
| 正常 PDF 元数据（对照） | 完成 | 有 | 未实际导出 |
| PDF 为零字节 | 完成 | 有 | `ARTIFACT_EXPORT_ARGUMENTS` |
| PDF 请求返回 DOCX 主产物 | 完成 | 无 | 未实际导出 |
| 只有报告，没有主产物 | 完成 | 无 | 未实际导出 |
| SHA-256 无效 | 完成 | 有 | `ARTIFACT_EXPORT_ARGUMENTS` |
| 产物引用为空 | 完成 | 有 | `STRING_RANGE` |
| 输出校验失败（负对照） | 失败 | 无 | 未实际导出 |

这证明成功展示存在校验缺口，不证明 JPEG C++ 引擎当前会生成这些异常结果。现有 JPEG Runtime 仍有结构、内容、大小、摘要和提交检查。建议在标记完成前要求有效的目标主产物，并让失败结果走既有产物释放流程。

## 2. P1：无证据的保真等级会被接受

位置：`entry/src/main/ets/viewmodel/NativeFidelityReport.ets:17`、`:27`。

模拟报告包含 `achievedTier: 'extreme'`、空指标、空证据以及 `requiresManualReview: false`，真实报告读取及任务存储仍接受并公开“极致保真”。目前检查验证数组类型和已有指标，却没有要求声称达到的等级具备足够的实际检测证据。

当前 JPEG Runtime 没有生成这份报告，缺失报告仍显示未判定；此次发现是异常报告可能导致误报。建议将“已生成文件”和“达到保真要求”分开判定，对没有充分证据的等级保持未判定或拒绝，不根据请求等级推断结果。

## 3. P1：PDF 反向路线的层叠顺序假设缺少 API 保证

位置：`entry/src/main/ets/services/PdfOfficeConverter.ets:98`、`:127`。

代码把 `getGraphicsObjects()` 返回数组下标作为对象 `zIndex`。本地实际 SDK 的 `@hms.officeservice.pdfservice.d.ts:2608` 说明对象按位置返回，例如从左到右或从上到下，并没有承诺原始绘制层叠顺序。因此，先前模拟 SDK 测试只能证明写出模块保留传入顺序，不能证明重建了源 PDF 的背景、图片、文字层级。

重叠对象可能改变遮挡关系；本轮没有执行真实 PDFKit 或渲染该故障。该模块尚未接入主应用，不影响当前 JPEG 路线。建议在取得可靠绘制顺序前明确拒绝无法确定层级的重叠对象，或采用能够提取绘制顺序的后端，再独立渲染核对。

## 4. P2：中文功能说明把目录称作支持的格式

位置：`entry/src/main/resources/base/element/string.json:173`。

中文标题为“一、支持的格式一览”，页面展示的是 18 种规划目录格式；英文已经是“Format catalog”。其余说明和路线状态多数明确标记规划，实际门禁也没有开放全部格式，但这个标题容易让人误认为这些格式都能转换。建议改为“收录的格式与规划能力”，保持运行能力和目录分开表达。

## 5. P2：旧宿主构建缓存不能作为当前代码证据

本轮首先使用 `tests/native/msvc-build/jpeg-pdf-prototype/hdm_jpeg_pdf_cli.exe`，它仍是 2026-10-01 的旧程序，拒绝 EXIF。增量构建只重新链接，未重新编译旧 `main.cpp.obj`；随后运行异常。该对象日期早于 2026-10-07 更新的 `ir.h`。旧 Ninja 配置的 MSVC 头文件依赖前缀还存在乱码，需要另行修复依赖跟踪。

改为全新 `tmp/capability-audit/native-build`，从当前源码构建所有 Native 测试、CLI 和原型测试，25/25 CTest 与 29 项 JPEG 独立解析/渲染检查通过。因此不能把旧 CLI 的失败归因于当前 JPEG 主应用；同时也不能只凭旧目录中的测试通过宣布当前源码已验证。建议后续验收使用干净构建，并检查头文件修改是否触发相关对象重编。

## 当前可以确认的边界

- 主应用的 Debug 白名单只有 `jpeg-pdf`，Release 不开放该路线；其余 42 条路线为规划。Office/PDF/OCR/媒体工厂仍为 `MissingConverter`。没有发现它们被主应用运行门禁误开放。
- 演示完成、真实转换完成和分享面板打开使用不同文案；任务记录明确说明只保留当前会话。没有发现界面把打开分享面板写成接收方已经收到文件。
- 保存/分享主机 6 项、Debug 路线 5 项、调度/报告既有 12 项通过；全新 Native 构建 CTest 25/25、JPEG 独立解析/渲染 29 项通过。没有进行新真机验证、接收方分享验收或首次断网验收。
- Word/PPT→PDF 仍待初始化修复后的真实导出；PDF→Word/PPT 是受限实现，实际 PDFKit 提取、版式和主应用接入未验收。

异常返回复现：[结构化记录](../tests/generated/capability-claims-audit.json)。本地复现程序：`tmp/capability-audit/reproduce.cjs`。全新构建日志：`tmp/capability-audit/native-fresh-build.log`；CTest 日志：`tmp/capability-audit/native-fresh-ctest.log`；独立 JPEG 核对：`tmp/capability-audit/jpeg-metadata.json`。原有设备验证报告未覆盖或改写。
