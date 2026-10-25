# 四条 PDF 路线：字体修复与候选版验收

**后续结果：** 本文对应的完整设备尝试为 10 项中 1 项通过、9 项错误，不能视为通过。前台 Ability 依赖、关闭顺序与报告检查的后续代码修改及新包见 [2026-10-25 记录](FONT-RELEASE-CANDIDATE-20261025.md)。本文下方的“通过”仅指对应的主机或构建检查。

日期：2026-10-23。范围仅 JPEG、PNG、DOCX、PPTX → PDF；其他 39 条路线保留禁用。此前的设备记录见 [10 月 14 日样例验收](DEVICE-ACCEPTANCE-20261014.md)，不能直接作为本候选包的运行证据。

## 本轮修改

- 包安全扫描仍检查所有 XML、关系、媒体、宏、保护及资源上限；字体需求单独分析实际文本、使用中的样式和主题、对应脚本、编号、引用的页眉页脚与脚注、幻灯片版式/母版。未使用声明不再一律计为缺失字体。
- 正常字体仍默认拒绝缺失，逐文件明确批准后才允许替代。私用字符和符号关联其实际字体检查，不再因为其他位置缺少普通字体就误拦已有图标。
- 既有转换结果新增可选 `fontDiagnostics: { family, part }[]`，失败和批准后的结果均可携带。Native、ArkTS、快照、任务记录和结果页保持一致；旧结果可省略字段。字体库存不可用、缺字、缺字体与无法解析的字体关系分别提示。
- 普通缺字体失败会保留任务拥有的源文件副本。用户在结果/历史中选择“允许字体替代并重试”，再次确认版式风险后，才以新任务及授权策略重新检查、转换。清空记录或关闭应用会释放保留输入；图标/缺字失败不开放这种重试。
- 继续使用现有字体与离线引擎，没有将宋体/黑体伪装为已安装，也没有将缺失原字体名单当成实际替换映射。

当前拒绝无法可靠解析的字体关系，例如带字体覆盖的条件表格样式、编号样式链接、主题覆盖或不支持的脚本主题映射。不能通过批准替代跳过此检查。该子集限制不等于文件损坏或字体安装失败。

## 电脑端弹窗的定位与修复

`hdm_runtime_tests.exe` 曾报告 `Run-Time Check Failure #2`、变量 `error` 周围栈损坏。调查发现旧 MSVC/Ninja 缓存对测试对象记录 **0 个头文件依赖**，测试对象停留在 10 月 13 日，而 Runtime 已使用扩展后的新结构；旧规则中的本地化 `/showIncludes` 前缀发生了编码错配。

统一在 UTF-8 代码页下配置和编译，并从全新缓存重建后，测试对象正确记录 45 个依赖，其中包括 `converter.h`。原 `native-build` 目录随后也重新配置并完整重建，26/26 CTest 通过。`/RTC1` 和 Debug CRT 检查保留；测试程序将运行时诊断写入 stderr 并失败退出，不弹出阻塞桌面的调试窗口。

推荐执行 `tests/run-native-windows.ps1`。脚本在相同代码页配置/构建，并核验 Ninja 确实跟踪 `converter.h`；不通过时不能采用测试结果。

## 本轮主机与构建证据

| 检查 | 结果与边界 |
| --- | --- |
| Native CTest | 26/26，包括字体授权、图标绑定及 NAPI 字体诊断；不是手机引擎运行 |
| 实际 OOXML 字体检查 | 36 项，覆盖未使用声明、样式/主题/脚本/编号/页眉/脚注/表格/母版、占位符继承及安全扫描 |
| ArkTS 字体诊断与重试 | 17 项，使用真实业务代码，Native/文件系统为模型；覆盖旧结果兼容、快照隔离、授权、保留输入、清理 |
| 原文档 CLI | 38 项；Office 为包检查，JPEG/PNG 包含主机实际转换与独立 PDF 检查 |
| 资源与 PDF 生命周期模型 | 23 项；不替代真实解压、引擎和 PDFKit 验收 |
| 保存分享模型 | 13 项，含关闭后回读、摘要错误、短读写、取消和失败恢复 |
| Release 主应用与测试包 | SDK 签名构建通过；包内引擎/资源结果见 `tests/generated/core-routes-release-hap-validation.json` |

候选包：`entry/build/default/outputs/default/entry-font-rc-20261023-signed.hap`。摘要及最终验收状态见 `tests/generated/font-release-candidate-20261023.json`。签名包、签名配置、原始手机日志和用户文件不进入公开仓库。

设备 `CorePdfSmoke` 已扩展为 10 个用例，新增默认不批准替代的 DOCX/PPTX 正例、真实缺失普通字体的拒绝/批准及结构化诊断、批准与不批准均拒绝缺失图标。测试包与主应用必须配套安装：

```text
hdc install -r entry/build/default/outputs/default/entry-font-rc-20261023-signed.hap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b com.example.os_softwaredevelopment -m entry_test -s unittest OpenHarmonyTestRunner -s class CorePdfSmoke -s timeout 180000 -s captureCorePdf true
```

## 发布前必须关闭的项目

- 用户原失败 Word 或其认可的等价真实文件，确认具体缺失字体及转换结果。目前不能判定该用户问题已关闭。
- 四条路线分别通过主应用选择文件、转换、保存、重新选取打开、分享接收端收到且能打开。发送目标及动作由用户在真机选择，自动测试不向联系人发送文件。
- DOCX/PPTX 与用户认可的参考 PDF 逐页核对文字、数字、表格、图片、符号、遮挡与分页；替代导致的差异需用户确认。
- 同一候选包的首次断网初始化、连续任务、取消、交付期间离开页面与资源使用记录。保留历史证据但不能据此冒充本包通过。

这些条件未满足时，路线保持 `experimental`，PR 保持草稿，不合并、不上架。
