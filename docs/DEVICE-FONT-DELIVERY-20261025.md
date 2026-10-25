# 2026-10-25 真机字体与四路线交付检查

## 当前结论

同一份 Release 主应用在已连接的 HarmonyOS API 24、arm64 手机上通过了自有样例的 JPEG、PNG、DOCX、PPTX → PDF 转换、系统选择器保存、重新选取打开及系统分享面板检查。没有安装替代引擎，也没有卸载应用或清除用户数据。

这不是发布放行。用户明确选择跳过接收端验证；参考 PDF 版式确认、首次断网初始化、取消和资源测量等仍未完成。其他 39 条路线继续保留但禁用。

## 本次实际修复

最初 Core 10 项全部在测试上下文初始化时报错：`Parse param context failed, must be a context of stageMode.`，尚未进入转换。`AbilityDelegator.getAppContext()` 返回的包装上下文不能直接传给此设备上的全局 `createModuleContext`。

测试辅助代码现在先调用 `getApplicationContext()`，再创建主应用的 `entry` 模块上下文。新增包装上下文的主机失败回归，修复后 5 项通过；真机默认引擎用例不再获取前台 Ability。真实文件选择器继续要求 UI 上下文。此修改不改变主应用字体授权或转换行为。

随后增加自有宋体、黑体 Word，以及按路线重新打开公共目录中保存 PDF 的检查。测试包只提供样例和核验代码，转换仍使用主包内真实引擎。

## 字体问题复现

用户无法确认原失败 Word，明确同意另建文件测试。本次自建 `core-common-fonts.docx` 含宋体正文、黑体标题、页眉页脚、中英文、金额、表格、图片及 ✓ → ©；另含一个从未使用的不存在字体样式。

1. 主应用未批准替代时准确拒绝，并显示宋体、黑体及正文、页眉、页脚位置。
2. 未使用的 `HDM Missing Unused Font` 没有进入诊断或阻断。
3. 点击“允许字体替代并重试”，确认风险后，不重新选文件即转换成功。
4. 独立解析结果包含正文、标题、页眉、页脚、金额和符号，A4 一页，表格及图片可见；实际 PDF 字体资源包含 HarmonyOS Sans SC 和 DejaVu Sans。这是输出资源观察，不是逐字族替换映射。

因此可以确认这份样例缺少原宋体、黑体，而现有引擎和中文替代字体能够工作。不能据此断言用户原文件具体缺什么字体，或保证替代后与 Word 原字体版式完全一致。

另有真机回归确认：内置字体默认策略可转换；真实普通缺失字体默认拒绝、批准后通过；缺失图标字体即使批准普通替代仍拒绝。默认正向用例没有统一预先批准替代。

## 最终包与结果

主包 SHA-256：`c2e227482a35e0af2f35cef6ee667b84b3444a8bb58afc36bd5a65bf5ac72a6f`。

最终测试包 SHA-256：`269100435a76bc0cb22b1c0d4e70fa6b75e5830b11e6a1ede713a91ee17c0787`。

包内静态检查通过：235 个共有原生库逐字节一致，测试包没有替换主引擎的 `libentry.so`；主包有 3284 个离线 Office 资源文件，未声明 INTERNET 权限。静态核对与下列实际运行是分别记录的证据。

| 真机检查 | 结果 |
| --- | --- |
| CorePdfSmoke | 11/11；0 Failure、0 Error、0 Ignore |
| JpegDebugSmoke | 2/2；包含 EXIF/ICC 图片和负向探测 |
| SavedPdfReadback | DOCX、PPTX、PNG、JPEG 各 1/1 |
| Core 独立解析与渲染 | 8 份 PDF、10 页；文字、数字、页数、页面尺寸和图片检查通过 |
| 已保存 PDF 独立解析与渲染 | 4 份、5 页；通过 |
| 主应用系统保存 | 四路线均显示保存成功，保存逻辑关闭后重新打开 URI 核验摘要 |
| 主应用系统分享面板 | 四路线均打开，显示对应 PDF 名称和大小 |
| 分享接收端 | 用户选择跳过；未验证发送、接收或接收端打开 |

实际查看了 Core 的全部 10 页渲染，包括中文、表格、图片、符号、页眉页脚，没有发现本样例中文字或对象丢失、裁切或遮挡。最终重跑的页面与已查看页面像素一致。保存后的 Word 页面另行查看，PPTX/PNG 保存页面与已查看的引擎页面像素一致。

PNG 提取图片与源样例像素一致；JPEG 原始图片数据保持一致，EXIF 方向、ICC 内容和独立渲染检查通过。Office 各次 PDF 元数据可导致文件摘要不同，不能把不同次导出的摘要差异直接判为内容损坏。

脱敏结果及输出摘要见 [设备结果](../tests/generated/device-font-delivery-20261025.json)。原始手机日志、UI 树、HAP 和本地 PDF 保留在忽略目录中，不上传公共仓库。

## 复测入口与剩余放行条件

最终测试包运行 `CorePdfSmoke` 默认应为 11 项，`JpegDebugSmoke` 应为 2 项。必须用 `tests/check-ohos-test-report.py` 检查完整终止标记与计数，不能只看 HDC 进程返回值。

`CorePdfSmoke -s fixtureLabel docx-common-fonts -s publishFixture true` 可将自有 Word 通过保存选择器发布到用户选定目录；`pptx`、`png` 同样可用。`JpegDebugSmoke -s publishJpegFixture true` 发布带 EXIF/ICC 的自有图片。发布需要前台 UI；默认引擎回归不弹选择器。

主应用保存后运行 `SavedPdfReadback -s savedFixture docx-common-fonts|pptx|png|jpeg -s captureCorePdf true`，手动选择刚保存的自有 PDF。这里的竖线表示四个可选值，实际命令只传一个值。PDFKit 与独立解析共同检查保存结果。

仍须完成：接收端实际收到并打开；用户认可的参考 PDF 逐页对照与替代版式确认；首次断网初始化；取消、交付期间离开页面、连续任务和资源使用测量。原 Word 未找回，本次仅关闭等价样例复现与当前交付链路检查，不把全部字体和任意复杂文档质量标为通过。保留 experimental 和草稿 PR，不合并、不上架。
