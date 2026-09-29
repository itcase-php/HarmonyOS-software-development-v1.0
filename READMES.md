# HarmonyOS软件开发v1.0

基于 HarmonyOS Stage 模型的原生文档转换工具工程，采用 **ArkTS / ArkUI 上层业务 + C++ / NAPI 底层能力**架构。当前版本侧重交互流程、配置驱动的路线规划、保真度参数管道及 Native 接入框架。

公共仓库：<https://github.com/itcase-php/HarmonyOS-software-development-v1.0>。仓库地址使用英文字符，软件展示标题保留“HarmonyOS软件开发v1.0”。许可证为 [MIT](LICENSE)。按交付要求，另提供同内容的 [READMES.md](READMES.md)。

使用 DevEco Studio 打开本仓库根目录，即包含 build-profile.json5 的目录；原开发目录为 `D:/HarmonyOS/harmonyOS`。不要打开其父目录或 `outputs`。

已将 `outputs/harmony-doc-manager-v1-design` 的全部 21 个交付文件迁入正式 Stage + Native C++ 模板。当前有首页、格式浏览器、转换演示、任务记录、功能指南五个页面，支持搜索/分类/详情、格式与路线选择、保真度设置与确认、五阶段进度、排队/暂停/取消和历史清理。转换页与历史页可展开模拟保真度报告；真实转换引擎仍未实现，演示不会生成实际文件。

## 当前功能与边界

| 范围 | 当前状态 |
| --- | --- |
| 页面 | Index、FormatBrowser、ConverterPage、TaskHistory、FeatureGuide 五页及页面导航 |
| 格式与规划 | 18 种格式、43 条规划路线；单文件路线、意图、最低保真等级筛选与质量模式排序 |
| 保真度控制 | 快速/均衡/高保真、转换意图、最低等级、路线说明及执行前配置确认 |
| 演示任务 | 2/3.5/6 秒活动时长，单并发 FIFO、暂停、恢复、取消与会话历史；退出应用不持久化 |
| 报告 | 演示报告展开查看；Native 报告读取接口与上下文/指标校验已预留 |
| 原生层 | 13 个 Native 接口、统一错误码、IR/资源预算契约及五类引擎占位 |
| 国际化与无障碍 | 保真度相关组件、路线提示和报告的中英文资源及主要控件读屏标注；未覆盖全部旧页面文案 |

**当前真实可用转换路线为 0。** UI 继续走 demo，不读取用户文件、不生成转换文件，也没有实测保真数据。Native 分支要求已有授权文件、session/workspace 和 available 路线；不提供把演示文件名当作真实输入的开关。真实引擎、文件授权/导出、持久化、后台调度和设备验收仍待开发。

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
node tests/check-design.cjs
node tests/check-migration.cjs
```

最新开发记录中，52 项宿主检查通过，应用包与 ohosTest 测试包编译通过，包内资源完整性检查通过。Hypium 源码通过宿主断言适配器执行，Native 导出在分支测试中使用模拟对象；**这些结果不等于真实转换、设备 Hypium、Previewer 点击或读屏验收**。详细记录在 tests/generated；本地绝对路径与历史产物哈希用于溯源，不是已上传二进制的下载地址。

设备安装仍需通过 DevEco 使用合法调试签名；根工程 signingConfigs 当前为空，构建生成未签名包。不要提交自己的私钥、密码或个人签名配置。

## 开发文档

- [目录作用与修改方法](docs/工程目录分析与修改指南.md)
- [交互功能与使用说明](docs/交互功能与使用说明.md)
- [保真度控制与参数管道](docs/保真度控制与参数管道.md)
- [组件、任务模型与 Native 分支优化](docs/组件与任务调度优化说明.md)
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

生成器先运行配置验证，再生成 ArkTS 缓存、Native 元数据与引擎注册表、Native 类型声明和 rawfile。现有引擎实现不会被生成器覆盖。生成后按正常 Hvigor 流程构建。

`tools/migrate-output-package.cjs` 是已经执行的一次性导入记录，后续不要重复运行。日常修改本工程源码；`docs/migration-source` 是原交付包的只读溯源副本。
