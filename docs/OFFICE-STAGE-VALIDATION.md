# Office 独立验证阶段

2026-10-07。已按用户批准采用 LibreOffice 26.2.6.2；PDF→Word/PPT 以文字和主要对象可编辑为目标。手机现已断开，当前交付是运行适配、构建和代码验证，四条路线尚未通过真实转换验收。

| 路线 | 当前已有实现 | 尚未完成 |
| --- | --- | --- |
| DOCX→PDF | arm64 引擎、Stage 打包、真实 LOK 加载/导出调用、文字表格图片样例 | 修复后设备初始化、实际导出和版式核对、主应用接入 |
| PPTX→PDF | 同一引擎及独立加载/导出调用、可编辑文字表格图片样例 | 同上，必须单独验收 |
| PDF→DOCX | PDFKit 文字/图片提取调用、坐标与层叠顺序重建、可编辑文本框与图片写出；通过模拟 SDK 流程及真实 SDK 编译 | 实际 PDFKit 提取验证、完整保护状态探测、字体资源清单接入、回读和渲染核对、主应用接入 |
| PDF→PPTX | 同一对象读取模块、可编辑文本形状和图片写出、每页一张幻灯片；通过模拟 SDK 流程及真实 SDK 编译 | 同上；混合页面尺寸目前明确拒绝 |

`OfficePackageWriter` 接受已测量的页面对象。新增 `PdfOfficeConverter` 使用实际 PDFKit 接口读取文字、字体、字形边界及图片，经坐标转换后调用写出模块；Stage 的 `PdfRebuildProbe` 已改为调用该流程，不再输出固定样本文字。该流程尚未在真实 PDFKit 运行，正式 Office/PDF 工厂仍返回 `MissingConverter`，没有增加路线白名单。

这是受限子集的代码实现：只接受未旋转、未裁剪的页面，以及已明确匹配可用字体的文字和独立图片；旋转、透明、裁剪、注释、矢量/Form/渐变对象及缺失字体均返回不支持。扫描图像需要 OCR，目前拒绝，不把整页图片作为可编辑转换。表格语义、复杂对象与排版保真仍未实现。文字框行高只是初始估算，必须进行参考渲染核对。

入口还要求调用方提供与该沙箱副本绑定的可信、已完成保护状态探测结果，拒绝签名、DRM、加密和未知状态；随后额外检查 PDFKit 加密状态。该参数不是保护状态探测器，主应用 PDF 完整探测尚未实现。Stage 只显式放行本地生成、已知未签名的固定样例，不能据此开放任意用户文件。总量限制为 100 MiB 输入、100 页、5000 对象、单图 1600 万像素、PNG 总量 8 MiB、输出包 16 MiB。

## UNO 运行适配

手机实测已加载主库并找到 LOK 入口，初始化随后失败。原始错误为：

```text
Cannot open uno ini file:///data/storage/el1/bundle/libs/arm64/unorc
```

HAP 的动态库目录与沙箱运行资源目录不同，上游默认在库旁寻找 `unorc`。新增 OHOS 补丁让 `cppu::getUnoIniUri()` 使用明确的 `LO_OFFICE_PROGRAM_URL`，探针将其设为沙箱内的 `office-probe/program`。`LO_LIB_DIR` 和 `URE_INTERNAL_LIB_DIR` 则指向实际安装的库目录，服务注册和类型继续从资源目录读取。

回归编译实际 `paths.cxx`：未打补丁的代码无法通过分离目录用例；修复后的代码通过正确路径、缺失配置和非法路径三个用例。这是主机选择 OHOS 分支的检查。对应 arm64 库已增量重建并打入新包，手机断开后未运行该修复。跨库 UNO 异常的类型捕获也仍待继续验证，探针已保留具体阶段和原始错误诊断。

## 验证证据

- 写出模块通过中文、补充字符、XML 转义、换行、图片、分页和非法输入检查。独立 Python 核对 ZIP CRC、内部关系、页面尺寸、文本对象与图片；PPT 文字修改、保存并重新打开通过。
- 微软 Open XML SDK 3.3.0 检查 DOCX/PPTX 均为零结构错误。发现的 Word 属性命名空间、元素顺序和换行问题已修复。采用[官方结构验证方法](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-validate-a-word-processing-document)，该检查不证明外观保真。
- PDF 反向模块通过两条模拟 SDK 转换流程和 21 项失败/控制用例，包括保护状态门禁、加密、旋转、裁剪、字体缺失、数量限制、图片打包失败、文字提取不一致及取消；也检查提前失败时释放尚未处理的图片。背景图片与文字层叠顺序的回归已修复。
- 对模拟 SDK 流程生成的 DOCX/PPTX，用独立解析器核对文本可编辑对象、图片、页数、尺寸、坐标和层叠顺序，微软结构验证均为零错误。模拟 SDK 不验证实际 PDF 读取结果。
- Stage 和 JPEG 主应用 Debug 包构建成功。Stage 编译了实际 `PdfOfficeConverter`、写出模块与 PDFKit 调用，尚未执行新的设备测试。
- 更新后的目标静态检查通过 241 个 ELF。独立 HAP 包含 236 个 ELF64/AArch64 库、修复后的 UNO 库、配置、字体及许可；包体约 388 MB，解压资源约 163 MB，尚未优化。
- 当前源码重新构建后的 Native CTest 25/25、保存分享主机回归 6/6 通过。本阶段没有新增真机测试通过项。

证据：[反向模块代码验证](../tests/generated/pdf-office-code-validation.json)、[反向产物结构验证](../tests/generated/pdf-office-openxml-validation.json)、[运行包检查](../tests/generated/office-stage-package-validation.json)、[OOXML 检查](../tests/generated/office-package-validation.json)、[微软结构验证](../tests/generated/office-openxml-schema-validation.json)、[UNO 回归](../tests/generated/office-uno-resource-regression.log)、[Stage 构建](../tests/generated/office-stage-build.log)、[主应用构建](../tests/generated/office-main-build.log)、[Native 回归](../tests/generated/office-native-regression.log)。此前完整构建记录保留在 `OFFICE-26.2-PORT.md`，其中设备状态属于当时的快照。

## 重新连接设备后

先确认并恢复 JPEG 主应用。Office 探针复用了现有签名和 bundle，会替换手机上的主界面。本地已保留断开前的主应用包：`tmp/offline-engines/jpeg-main-before-office.hap`，SHA256 为 `725baca4047c47f5a89f9b776adf0d5a7104773b4e05137ecda018b24d60593d`。当前主应用也重新构建成功，但尚未重新安装；手机恢复状态没有确认。

随后验证新包的初始化，分别取回 DOCX/PPTX 导出的 PDF，核对页数、尺寸、关键数值、表格、图片和逐页外观，通过后接入主工程。反向路线先验证 PDFKit 的实际坐标、字体、图片和裁剪行为，再核对可编辑产物及完善结构重建；不能把完整页面截图包装为已完成的可编辑转换。
