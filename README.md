# HarmonyOS软件开发v2.0

基于 HarmonyOS Stage 模型的原生文档转换工具工程，采用 **ArkTS / ArkUI 上层业务 + C++ / NAPI 底层能力**架构。已完成交互流程、完整目录规划、保真度参数管道、核心测试、rawfile 校验、调度防重入及相关国际化。已接入真实文件选择、受控副本和真实提交入口；本次按批准方案拆分转换页、观察 VM 与可注入服务，优化索引、错误诊断和资源清理，保留原功能。

公共仓库：<https://github.com/itcase-php/HarmonyOS-software-development-v1.0>。仓库地址使用英文字符，软件展示标题保留“HarmonyOS软件开发v1.0”。许可证为 [MIT](LICENSE)。按交付要求，另提供同内容的 [READMES.md](READMES.md)。

使用 DevEco Studio 打开本仓库根目录，即包含 build-profile.json5 的目录；原开发目录为 `D:/HarmonyOS/harmonyOS`。不要打开其父目录或 `outputs`。

已将 `outputs/harmony-doc-manager-v1-design` 的全部 21 个交付文件迁入正式 Stage + Native C++ 模板。当前有首页、格式浏览器、转换演示、任务记录、功能指南五个页面，支持搜索/分类/详情、格式与路线选择、保真度设置与确认、五阶段进度、排队/暂停/取消和历史清理。转换页与历史页可展开模拟保真度报告；真实转换引擎仍未实现，演示不会生成实际文件。

## 当前功能与边界

| 范围 | 当前状态 |
| --- | --- |
| 页面 | Index、FormatBrowser、ConverterPage、TaskHistory、FeatureGuide 五页及页面导航 |
| 格式与规划 | 完整保留 18 种格式、43 条规划路线；启动及独立预览立即提供完整目录，资源加载失败不会缩减；单文件路线、意图、最低保真等级筛选与质量模式排序保持原行为 |
| 保真度控制 | 快速/均衡/高保真、转换意图、最低等级、路线说明及执行前配置确认 |
| 演示任务 | 2/3.5/6 秒活动时长，单并发 FIFO、暂停、恢复、取消与会话历史；退出应用不持久化 |
| 文件输入 | Stage Picker、最多 10 文件管理、单文件 100 MiB/会话 300 MiB、分块副本与 SHA-256、信息卡片/移除/清理；真实提交保持单文件，设备验收待执行 |
| 报告 | 演示报告展开查看；Native 报告读取接口与上下文/指标校验已预留 |
| 原生层 | 13 个 Native 接口、统一错误码、IR/资源预算契约及五类引擎占位 |
| 国际化与无障碍 | 保真度相关组件、路线提示和报告的中英文资源及主要控件读屏标注；格式浏览器文案已覆盖，其他旧页面尚未全部国际化 |

**当前真实可用转换路线为 0。** 未选择真实文件时，原演示不读取文件、不生成转换结果。新入口可通过 Picker 授权并复制文件，但 C++ initializeSession/registerWorkspace 仍占位，真实提交如实记录失败，不回退为演示成功。输入推断不是内容/保护验证；原 Native 门禁保持。真实会话/引擎、输出导出、持久化、后台调度及设备验收仍待开发。

## 工程结构

固定核心模块及顺序如下：

1.ArkTS 层：页面、组件、模型、格式注册、转换规划、任务管理、NativeBridge

2.C++ 层：NAPI 入口、转换器接口、错误码、IR 结构、资源限制、保真校验、PDF/Office/Media/Image/OCR 引擎占位

3.共享配置：formats.json、conversion-matrix.json

4.文档：架构、转换矩阵、AI 编程规则、隐私、错误码、保真策略、上架检查清单

5.测试：格式矩阵和 DRM 类格式阻断测试

```text
AppScope/                    应用元数据和公共资源
entry/src/main/ets/           ArkTS 页面、组件、模型、服务和任务管理
entry/src/main/cpp/           NAPI、C++ 契约与引擎占位
entry/src/main/resources/     路由、格式配置副本、中英文资源
entry/src/test/               本地 Hypium 核心用例
entry/src/ohosTest/            设备测试入口
shared/format-registry/       格式、路线、Schema 与错误码配置
tools/                       配置生成及产物检查
tests/                       宿主逻辑、设计和迁移检查及验证记录
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
node tests/check-fidelity.cjs
node tests/check-refactor.cjs
node tests/check-hypium-host.cjs
node tests/check-audit.cjs
node tests/check-input-management.cjs
node tests/check-architecture.cjs
node tests/check-design.cjs
node tests/check-migration.cjs
```

最新记录中，173 项宿主检查通过（交互 15、保真 13、原重构 12、Hypium 源码 61、审计/目录 16、输入管理 35、架构 21）。应用及 ohosTest 编译、HAP 检查通过；最新日志为 tests/generated/architecture-step9-build.log 和 architecture-test-hap-build.log，汇总见 architecture-validation-report.json。转换页四个观察 VM/六个组件、实例服务、分类工厂和索引已实现；保留 100 条历史及跨页运行，闲置未提交会话默认 30 分钟 TTL。原任务方法实现已获批重构，旧输入阶段的哈希仅为历史基线；原 18/43 配置、Native 协议、C++ 和路由保持。**宿主 SDK/Native 使用替身，这些检查不等于真机 Picker、真实转换、设备 Hypium、Previewer 点击、实际响应式刷新或读屏验收**。hdc 无连接设备，独立编辑器工具不可用，SDK 能力及未签名警告仍有记录。

设备安装仍需通过 DevEco 使用合法调试签名；根工程 signingConfigs 当前为空，构建生成未签名包。不要提交自己的私钥、密码或个人签名配置。

## 开发文档

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
