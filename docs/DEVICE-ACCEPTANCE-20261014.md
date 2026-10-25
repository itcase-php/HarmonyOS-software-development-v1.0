# 2026-10-14 Release 真机样例验收

用户重新连接设备后，使用鸿蒙 arm64、API 24 真机安装并测试签名 Release 主应用。主应用最终仍安装在手机上，已恢复到首页，显示 Native 已连接及 4 条可执行路线。

## 本轮发现并修复

**导出文件句柄过期。** 修复前，DOCX / PPTX 都已越过引擎初始化和导入，但被 `NATIVE_PDF_STRUCTURE` 拒绝。Office 可能替换目标路径，Runtime 仍在导出前打开的候选句柄上做检查。现在写入结束后重新打开实际导出路径，再执行原有 PDF 结构检查；修改后 DOCX、PPTX 和 PNG 三个设备用例全部通过。没有放宽结构检查或跳过系统 PDFKit。

**中文 Word 的勾号真实丢失。** 中文混排 DOCX 样例被 `OFFICE_TEXT_MISSING` 拦截，独立提取及渲染确认 U+2713 勾号丢失，并出现不合适的符号字体回退。字体配置现在将内置 DejaVu Sans 加到弱回退候选末尾，并在重启时核对配置内容、自动替换旧缓存。修复后勾号、箭头、版权符号和中文文字均保留，PDFKit、pypdf 和页面渲染通过。

引用字体默认仍拒绝缺失；只有用户明确批准才允许普通字体替代。原字体优先级、安全检查和私用区图标缺字拦截保持生效。新增缓存回归在修复前失败，修复后资源/PDF 生命周期主机模型 23 项通过。

## Release 设备结果

| 用例 | 结果 |
| --- | --- |
| DOCX → PDF | 通过，2 页，612 × 792 pt，正文、表格、数值、图片与页眉核对通过 |
| PPTX → PDF | 通过，2 页，960 × 540 pt，两页文字、数值、表格与图片核对通过 |
| PNG → PDF | 通过，系统 PDFKit 解析及任务清理后的复制 / 摘要回读通过 |
| 中文 DOCX | 通过，中文表格、678.90 / 12345 / 98765 及 ✓ → © 保留 |
| 中文 PPTX | 通过，中文、关键数值、✓ → © 和图片保留 |
| 缺失私用区图标字形 | 正确拒绝，`FONT_MISSING / OFFICE_GLYPH_MISSING`，不产生输出 |
| JPEG 基线、EXIF/ICC | 两个真机用例均通过 |
| 保存后重新选取 PDF | 通过，公开保存的 2 页 PDF 可重新打开，正文及关键数值通过 |

CorePdfSmoke 为 **6/6**，JPEG 为 **2/2**，保存后的重新打开为 **1/1**。读取 Hypium 的测试总数、Failure、Error 和 Pass 字段确认结果；没有把 HDC 返回 0 当作测试通过。测试 HAP 不含替代的 `libentry.so`，使用主应用 Release Native；两包共有的预编译库字节相同。

设备导出的五份受控样例 PDF 共 7 页，全部经过摘要核验后的分块采集、pypdf 严格解析、页数 / 尺寸 / 文字 / 数值检查及 Poppler 渲染，并逐页查看。图片资源数量不等同于页面实际绘制数量；绘制外观另由页面渲染检查。

## 主应用完整流程

从 PDF 详情的“将文件转为 PDF”进入转换页，选择 DOCX，通过系统选择器导入仓库自有 Word 样例，明确批准字体替代，再确认真实转换。真实队列完成后进入**任务记录**，点击“保存 PDF”并选择 Download，页面显示“PDF 已保存”。保存接口已经关闭并重新读取目标文件，核对大小和 SHA-256 后才报告成功。

随后点击“分享 PDF”，系统分享面板正常打开，显示正确的 PDF 文件名及约 22.94 KB 的大小。没有向联系人发送文件，也没有宣称接收方已收到。

再安装/运行独立读回用例，从系统文件选择器重新选择保存到 Download 的该 PDF，PDFKit 成功打开 2 页并核对正文和关键数值。重新采集的文件为 **22936 字节**，SHA-256 为 `f0cad253459da28e21d0deb83cea2dee4824ab688221321fe389eda4b4680b45`。电脑独立解析与渲染通过，两页渲染像素与对应的受控 DOCX 转换样例一致。测试的源 Word 和保存 PDF 留在 Download 中，没有操作其他用户文档。

## 构建与可复查证据

当前主包：`entry/build/default/outputs/default/entry-release-signed.hap`，**392699662 字节**，SHA-256：

`f5117138be3132975cd9afc1069f9d596f5d1647f72a7dc0ca540d9a99693967`

Native 主库 SHA-256：`517991e61831d42b218c35d289bd55c9eec0d148ecb33f0dd8a405f7d577a799`。235 个 Office 库、3284 个离线文件及已有 UNO 修复的包内校验通过；未声明 INTERNET 权限。原生主机 CTest 25/25、文档 CLI 38 项、资源/PDF 主机模型 23 项及交付主机模型 13 项通过。模型测试与实际设备结果分开记录。

机器可读证据：

- `tests/generated/core-device-release-validation.json`：Release 包摘要、实际测试计数、主界面流程、限制。
- `tests/generated/core-device-pdfs.json`：五份真机输出的摘要、页数、文字与字体资源。
- `tests/generated/saved-device-pdf.json`：公开保存后重新读取的 PDF。
- `tests/generated/core-routes-release-hap-validation.json`：静态包内检查，本检查本身不执行设备。

重新运行核心测试：

```text
hdc shell aa test -b com.example.os_softwaredevelopment -m entry_test -s unittest OpenHarmonyTestRunner -s class CorePdfSmoke -s timeout 180000 -s captureCorePdf true
hdc shell aa test -b com.example.os_softwaredevelopment -m entry_test -s unittest OpenHarmonyTestRunner -s class JpegDebugSmoke -s timeout 180000
```

Core 的 `-s fixtureLabel docx-cjk` 可单独选择样例；`-s publishFixture true -s fixtureLabel docx` 可通过系统保存选择器发布自有测试源文件；`SavedPdfReadback` 类会要求选择刚保存的样例 PDF。`tests/check-device-core-pdfs.py` 从受控 PDF 采集日志验证摘要并独立解析、渲染。原始设备日志、界面树、HAP、字体与 PDF 二进制保留本机，没有提交到公开仓库。

## 证据边界

本轮证明当前手机、Release 版本和这些受控样例可运行，并修复了实际暴露的问题。没有声称任意 Word/PPT 文件与 Microsoft Office 参考版式完全一致；复杂文档、全部字体及更多设备仍需扩充样本。分享接收方收取未测试。四条路线仍标为 `experimental`，其他 39 条路线继续禁用，没有仅凭一轮样例把全部发布资格标为通过。
