# HarmonyOS软件开发v2.0

**2026-10-25 代码候选版：修正批量测试对前台窗口的依赖、退出时 Native 关闭顺序及 Windows 验证脚本；主机回归和配套 Release 构建通过。上次设备测试实际为 1 项通过、9 项错误，本轮按要求未调试手机。当前包、证据与晚间验收清单见 [最新候选记录](docs/FONT-RELEASE-CANDIDATE-20261025.md)。**

**2026-10-23 候选版：修正 Office 未使用字体误拦截，增加缺失字族/使用部件诊断及明确批准后的源文件重试；四条路线仍等待完整发布验收。电脑端 MSVC 测试旧对象混用导致的栈检查弹窗已修复，内存检查保留。详见 [字体修复与验收记录](docs/FONT-RELEASE-CANDIDATE-20261023.md)。**

**2026-10-14 真机复验：补修 Office 导出文件句柄及中文/符号字体回退后，签名 Release 的 Core 6/6、JPEG 2/2、保存后重新打开 1/1 通过。五份真实 PDF 已独立解析、渲染并逐页检查；主界面 DOCX 转换、Download 保存和系统分享面板通过。当前证明受控样例与本机可运行，未宣称任意 Office 文件无损。详见 [Release 真机样例验收](docs/DEVICE-ACCEPTANCE-20261014.md)。**

基于 HarmonyOS Stage 模型的原生文档转换工具工程，采用 **ArkTS / ArkUI 上层业务 + C++ / NAPI 底层能力**架构。主应用收敛为 **JPEG、PNG、DOCX、PPTX → PDF**。图片核心静态编入 Native，DOCX/PPTX 使用真正的 LibreOfficeKit Writer/Impress。Debug 与 Release 均允许范围内的真实转换，实际引擎、输入和输出检查继续生效；`experimental` 表示设备与版式资格尚待验收，不再表示 Debug 专用。其余 39 条路线保留禁用。

公共仓库：<https://github.com/itcase-php/HarmonyOS-software-development-v1.0>。仓库地址使用英文字符，软件展示标题保留“HarmonyOS软件开发v1.0”。许可证为 [MIT](LICENSE)。按交付要求，另提供同内容的 [READMES.md](READMES.md)。

2026-10-07 历史验证：JPEG 支持受限 EXIF 方向/分辨率与 ICC，真机 Hypium 65/65 及真实样例的独立 PDF 解析/渲染通过。后续保存至 Download 的内容一致性、系统分享面板也已验证，接收方收取仍待验收；这些证据不等于本轮新包设备复验。详见[JPEG 兼容修复](docs/JPEG-METADATA-COMPATIBILITY.md)和[保存分享记录](docs/ARTIFACT-DELIVERY.md)。

使用 DevEco Studio 打开本仓库根目录，即包含 build-profile.json5 的目录；原开发目录为 `D:/HarmonyOS/harmonyOS`。不要打开其父目录或 `outputs`。

已将 `outputs/harmony-doc-manager-v1-design` 的全部 21 个交付文件迁入正式 Stage + Native C++ 模板。当前有首页、格式浏览器、转换演示、任务记录、功能指南五个页面，支持搜索/分类/详情、格式与路线选择、保真度设置与确认、五阶段进度、排队/暂停/取消和历史清理。转换页与历史页可展开模拟保真度报告；演示不会生成实际文件。首页帮助按钮旁新增 EN/中切换，可在运行时更新五页、组件与会话任务文字，并保存语言选择。

## 当前功能与边界

| 范围 | 当前状态 |
| --- | --- |
| 页面 | Index、FormatBrowser、ConverterPage、TaskHistory、FeatureGuide 五页及页面导航 |
| 格式与规划 | 原 18 种格式、43 条路线定义保留；当前 UI 仅 5 种格式、4 条单向路线，PDF 仅输出；其余 39 条入口和执行禁用，代码未删除 |
| 保真度控制 | 快速/均衡/高保真、转换意图、最低等级、路线说明及执行前配置确认 |
| 演示任务 | 2/3.5/6 秒活动时长，单并发 FIFO、暂停、恢复、取消与会话历史；退出应用不持久化 |
| 文件输入 | Stage Picker、最多 10 文件管理、单文件 100 MiB/会话 300 MiB、分块副本与 SHA-256、信息卡片/移除/清理；真实提交保持单文件，DOCX 主界面选取及授权副本已在真机验证 |
| 报告 | 演示报告展开查看；Native 报告读取接口与上下文/指标校验已预留 |
| 原生层 | 14 个 Native 接口；授权输入、深层格式/保护检查、image/office 调度、PDF 候选校验、提交与释放接入；PNG/Office 完成前要求系统 PDFKit 独立解析，Release 受控样例已通过；其他引擎代码保留禁用 |
| PDF 交付 | 系统保存与 ShareKit 分享副本关闭后回读核对大小和 SHA-256；交付完成前保留 Native 产物。主应用 DOCX 保存到 Download、重新打开及分享面板通过；接收方实际收取未测试 |
| JPEG→PDF | 真实单张 8 位 Baseline SOF0 灰度或三分量 JPEG 转换；主机运行时、独立 PDF 解析/渲染通过；Debug 与 Release 均执行，受产品范围、实际引擎、配置及输入校验约束 |
| PNG→PDF | 实际 libpng 解码与 RGB/透明度 PDF 写出；6 种模式主机转换及独立像素/渲染检查通过；Release 真机样例转换 / PDFKit / 产物复制通过；静态 ≤8 位，按实际物理分辨率计算尺寸，缺失时 96 DPI；ICC/动画等未支持 |
| DOCX/PPTX→PDF | OHOS arm64 内置 LibreOfficeKit Writer/Impress；Release 真机完成 Word 2 页、PPT 2 页及中文/符号样例，独立解析和逐页渲染检查通过；任意文档的版式等价性未保证；旧 DOC/PPT 未开放 |
| 国际化与无障碍 | 首页 EN/中运行时切换、五页与组件/任务/报告/提示/读屏文案统一翻译；358 个双语资源键；语言使用 AppStorage + PersistentStorage 保留；实际 Previewer 和设备重启验收待执行 |

当前 **4 条 experimental、39 条 planned、0 条 available**，四条已在 Debug 与 Release 开启真实执行；范围外定义保留禁用。签名 Release 候选包约 393 MB，Office 仅 arm64，首次资源准备要求缓存至少 400 MiB 可用空间。缺失引用字体默认拒绝，只有用户明确同意才允许内置/系统替代；Office 保真等级保持未判定。演示入口仅保留在 Debug。异常产物和无证据保真等级不显示为正常完成。本轮四条路线的 Release 受控样例已通过真机，DOCX 主界面保存及分享面板已验证；更多文档/设备及分享接收方仍需覆盖。详见[Release 真机样例验收](docs/DEVICE-ACCEPTANCE-20261014.md)与[历史阶段记录](docs/IMPLEMENTATION_STATUS.md)。

## 工程结构

固定核心模块及顺序如下：

1.ArkTS 层：页面、组件、模型、格式注册、转换规划、任务管理、NativeBridge

2.C++ 层：NAPI 入口、转换器接口、错误码、IR 结构、资源限制、image/office 实验引擎及保留禁用的其他引擎

3.共享配置：formats.json、conversion-matrix.json

4.文档：架构、转换矩阵、AI 编程规则、隐私、错误码、保真策略、上架检查清单

5.测试：格式矩阵和 DRM 类格式阻断测试

```text
AppScope/                    应用元数据和公共资源
entry/src/main/ets/           ArkTS 页面、组件、模型、服务和任务管理
entry/src/main/cpp/           NAPI、C++ 契约、图片/Office 引擎及其他占位
entry/src/main/resources/     路由、格式配置副本、中英文资源
entry/src/test/               本地 Hypium 核心用例
entry/src/ohosTest/            设备测试入口
shared/format-registry/       格式、路线、Schema 与错误码配置
tools/                       配置生成及产物检查
tests/                       宿主逻辑、设计和迁移检查及验证记录
prototypes/jpeg-pdf/          隔离原型与集成测试；受限核心源码进入 Native 构建
docs/                        设计、操作、实现边界及原交付溯源
hvigor/                      Hvigor 工程配置
```

## 开发与验证

当前工程配置和已验证环境使用 DevEco Studio 26、HarmonyOS SDK/API 26、BiSheng，Native 构建包含 arm64-v8a 和 x86_64。兼容范围以 build-profile.json5 为准，尚未验收更早系统版本。安装 DevEco 配套工具链及 SDK 后：

```powershell
git clone https://github.com/itcase-php/HarmonyOS-software-development-v1.0.git
cd HarmonyOS-software-development-v1.0
ohpm install
```

通过 DevEco 打开工程并构建 entry/default；预览入口为 entry/src/main/ets/pages/Index.ets。请使用交互预览模式验证点击，完整导航最终以模拟器/真机运行结果为准。本仓库不包含个人 SDK 路径文件、构建缓存、依赖安装目录、签名证书或未签名 HAP；local.properties 由本机工具配置。

宿主脚本需要 Node.js 及 DevEco 自带的 TypeScript。默认脚本保留原开发机工具路径；其他安装位置请先设置 HDM_TYPESCRIPT_PATH，例如：

```powershell
$env:HDM_TYPESCRIPT_PATH = 'C:/DevEco Studio/tools/arktsdoc/node_modules/typescript/lib/typescript.js'
node tests/check-interactions.cjs
node tests/check-copy-safety.cjs
node tests/check-fidelity.cjs
node tests/check-refactor.cjs
node tests/check-hypium-host.cjs
node tests/check-audit.cjs
node tests/check-input-management.cjs
node tests/check-architecture.cjs
node tests/check-design.cjs
node tests/check-migration.cjs
```

本阶段 ArkTS 宿主脚本全部通过，MSVC 主机 CTest 22/22、独立 PDF 集成检查 15/15 通过；应用及 ohosTest 编译、双 ABI HAP 与第三方许可文件打包通过。详见[分阶段验证记录](docs/VALIDATION-JPEG-PDF-PRODUCTION.md)。原 18/43 配置和 ArkTS 协议保持。**这些检查不等于真机 Picker、应用真实转换、设备 Hypium、Previewer 点击、读屏或发布验收**。`hdc` 无连接设备，构建包未签名。

设备安装仍需通过 DevEco 使用合法调试签名；根工程 signingConfigs 当前为空，构建生成未签名包。不要提交自己的私钥、密码或个人签名配置。

## 语言切换验证

用户审核的三项整理已完成：资源 Map 索引、PageHeader 去除重复翻译、删除旧 FidelityPolicy 标签方法。语言切换机制保持；性能与内存取舍、setLanguage 风险和验证情况见 [语言优化说明](docs/LANGUAGE-OPTIMIZATION.md)。

```powershell
node tools/generate-language-catalog.cjs --check
node tests/check-runtime-language.cjs
```

语言逻辑 8 项、交互 15 项、重构 12 项、架构 21 项与 Hypium 宿主 61 项通过；应用包编译零错误。两个历史脚本仍在本轮未改的 NativeProtocol 旧哈希断言处失败，未更新旧基线掩盖失败。设备/Previewer/真实重启验收待执行，详见[语言说明](docs/RUNTIME-LANGUAGE.md)。

## 开发文档

- [运行时中英文切换与验收](docs/RUNTIME-LANGUAGE.md)
- [语言改造实施审阅说明](spec/changes/runtime-language/implementation-review.md)

- [JPEG→PDF 生产接入分阶段验证](docs/VALIDATION-JPEG-PDF-PRODUCTION.md)
- [能力矩阵诊断与路线门禁复核](spec/changes/jpeg-pdf-production/capability-review.md)
- [本次已批准的修改范围](spec/changes/jpeg-pdf-production/approval-request.md)
- [本轮兼容优化与隔离原型验证](docs/VALIDATION-NATIVE-READINESS.md)
- [独立 JPEG→PDF 原型说明](prototypes/jpeg-pdf/README.md)
- [上阶段生产接入审核记录](spec/changes/native-readiness-and-copy-safety/implementation-review.md)
- [文件授权与输入管理](docs/文件授权与输入管理说明.md)
- [目录作用与修改方法](docs/工程目录分析与修改指南.md)
- [交互功能与使用说明](docs/交互功能与使用说明.md)
- [保真度控制与参数管道](docs/保真度控制与参数管道.md)
- [组件、任务模型与 Native 分支优化](docs/组件与任务调度优化说明.md)
- [格式目录恢复与回归验证](docs/格式目录恢复与回归验证.md)
- [上一轮审计改进与验证](docs/审计改进与验证说明.md)
- [迁移结果与实现边界](docs/IMPLEMENTATION_STATUS.md)
- [逐文件迁移清单](docs/MIGRATION_MANIFEST.json)
- [原始 V1.0 设计](V1.0初步功能开发方案.md)
- [验证与构建说明](docs/VALIDATION-MIGRATION.md)

修改格式或转换矩阵后，在工程根目录运行：

```powershell
node tools/generate-registry.cjs
node tests/check-migration.cjs
node tests/check-interactions.cjs
node tests/check-fidelity.cjs
node tests/check-refactor.cjs
node tests/check-hypium-host.cjs
```

生成器先运行配置验证，再从同一份 shared JSON 生成完整 ArkTS 目录、摘要元数据、Native 元数据与引擎注册表、Native 类型声明和 rawfile。现有引擎实现不会被生成器覆盖。FormatRegistry 立即提供完整的 18 格式/43 规划路线；rawfile 按需读取，以编译元数据的 SHA-256、schema/config 版本及数量校验后原子替换缓存。读取失败/超时可重试，并保留完整目录及演示功能；查询结果为深复制。真实 Native 路线继续要求资源校验通过、路线状态及原生发布证据满足条件。此机制不包含签名配置热更新。生成后按正常 Hvigor 流程构建。

`tools/migrate-output-package.cjs` 是已经执行的一次性导入记录，后续不要重复运行。日常修改本工程源码；`docs/migration-source` 是原交付包的只读溯源副本。
