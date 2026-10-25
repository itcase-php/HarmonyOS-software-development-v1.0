# JPEG→PDF 调试入口修复与下次真机验收

日期：2026-10-07。用户授权先完成代码层修复；本阶段不连接设备、不运行手机界面或 Previewer。

## 问题与修复范围

此前工作区的 JPEG 路线状态、打包 rawfile、生成目录与 Native 摘要不一致；仅把一处状态改为 available 不能打通正式任务入口。配置摘要不能充当引擎构建摘要，未完成真机验收也不能填写发布证据。

本次只允许 JPEG→PDF 在 Debug 中进行实验测试，DOCX→PDF、PPTX→PDF 的 Office 后端仍未接入。现有 18 种格式和 43 条路线保留，JPEG 以外的 42 条路线保持 planned。本轮没有新增库或 SDK；复用 API26 官方 Native SDK 与固定 libjpeg-turbo 3.1.4.1。

| 既有内容 | 必要改动 | 保留的边界 |
| --- | --- | --- |
| JPEG 路线 | planned 改为 experimental | 原操作、页面映射、保真配置、输入保护规则和资源预算未改 |
| 调试资格 | `shared/format-registry/debug-routes.json` 为唯一白名单源；生成 ArkTS 和 Native 白名单 | 仅 jpeg-pdf；planned 路线不会因 Debug 自动可执行 |
| ArkTS 入口 | 使用 DevEco 生成的 `BuildProfile.DEBUG`；预检查和入队使用同一 availableRoutes 判断 | 仍需完成资源校验、实际引擎能力检查与输入深层探测 |
| Native 执行 | CMake 仅在 Debug 定义 `HDM_NATIVE_DEBUG=1`；生产 NAPI execute 再次检查路线 | Release 拒绝本轮 experimental 路线；无伪造 releaseEvidenceId |
| 引擎能力 | 返回已链接 image 引擎的真实版本和构建清单摘要 | 模块存在与路线开放分别判断；不宣告 Office 能力 |
| 配置生成 | 运行 `tools/generate-registry.cjs` 同步源、rawfile、ArkTS 目录和 C++ 元数据 | 新 matrix SHA-256：`6880fe28fee8e12537bff1324723bc195f051313fc96bec85e0ff62569b0d31f` |
| 入口文案 | 更新四处原本永久显示“未开放”的中英文文案，并重新生成语言目录 | 不改无关文案；没有检测证据时不判定保真等级 |
| 历史保护测试 | 只允许已批准的 JPEG 状态/说明和前阶段报告序列化改动 | 原迁移快照及原哈希不改；其余配置、权限与接口继续检查 |

本轮没有调整字体策略、100 MiB 文件限制、300 页、192 MiB Native 预算或 180 秒时限，没有移除授权、摘要、保护状态、输出校验和受控产物管理。

## 构建摘要的含义

`production/build_manifest.cmake` 在构建目录生成清单和头文件。清单包含实际相关源码字节的 SHA-256、固定 JPEG 归档摘要与构建选项、目标 ABI、编译器、构建模式、编译标志、工具链与 SDK 元数据摘要。`buildHash` 是该清单按 LF 换行规范化后的 SHA-256，不是 `.so` 文件字节摘要，也不是配置摘要。Windows 工具生成的 CRLF 清单应先规范化为 LF 再复核。

清单不包含个人签名文件、文件正文、文件名、外部 URI 或用户文档。它写入构建目录，不以一份宿主摘要冒充设备库摘要。各 ABI 与 Debug/Release 的实际摘要记录在 [本轮验证记录](../tests/generated/jpeg-debug-repair-validation.json)。

## 已执行验证

| 层次 | 结果 | 实际覆盖与限制 |
| --- | --- | --- |
| 新增 ArkTS 门禁回归 | 4 项通过，先失败再修复 | 执行真实 registry、preflight、runner 代码；Native 为宿主模型，不代表手机转换 |
| Native CTest | 24/24 通过 | 生产 Runtime 的真实 JPEG 输入、PDF 结构/载荷校验、授权/摘要与产物复制，以及 Debug/Release 能力和报告序列化；宿主执行 |
| 配置与既有契约 | design、migration、audit、input-management、architecture、device-entry、fidelity、runtime-language、interactions、copy-safety、refactor 通过 | 精确限制本轮允许的配置差异；迁移契约保留此前已批准的 copyArtifactToFd |
| Hypium 来源宿主运行 | 61 项通过 | 注册测试源在宿主 SDK 模型中执行；不是实际设备 Hypium |
| 主应用 Hvigor | Debug / Release 均 BUILD SUCCESSFUL；arm64-v8a、x86_64 | 真实 ArkTS/Native 编译与签名；Debug 宏只出现在 Debug 命令中 |
| ohosTest Hvigor | Debug 签名测试包 BUILD SUCCESSFUL | 仅构建；本轮不运行设备测试 |
| 构建核对 | 四个 ABI/模式清单与当前源摘要匹配；最终主应用 `BuildProfile.DEBUG=true` | HAP 包含两种 ABI 的 libentry.so；不等于设备已加载 |
| 旧逐字节保护脚本 | check-native-preservation 失败，未修改或伪称通过 | 该 2026-09-30 历史检查首先拒绝本地签名配置；不能用于证明当前已批准阶段的所有文件仍与早期模板逐字节一致。对应现行契约另由上述测试核对 |
| 手机 / Previewer | 未执行 | 本轮没有安装、启动、截图、真实系统 Picker 或端到端验收 |

个人签名配置只留本地，用于构建；不提交 build-profile.json5、签名材料、HAP、原始日志或用户文件。前阶段设备结果见 [Office 前置验证记录](OFFICE-ENGINE-TOOLCHAIN-STATUS.md)，不得替代本阶段真机验收。

## 真机调试使用方法

本次代码位于已附到对话的独立工作区、分支 `codex/office-pdf-engine`。用 DevEco 打开该工作区并选择 default 产品、Debug 模式运行。工作区根目录为 `C:\Users\TX\.codex\worktrees\office-pdf-engine\harmonyOS`。已签名主应用为 `entry/build/default/outputs/default/entry-default-signed.hap`；本地另保存一份 `tmp/jpeg-debug-handoff/jpeg-pdf-debug-signed.hap`，并附无个人内容的 baseline JPEG 测试样例。

1. 先使用提供的 baseline.jpg 测试样例，选择 JPEG→PDF，切到真实文件输入并导入。该文件是仓库既有合成测试样例，不是用户照片。
2. 预检查通过后确认提交，检查执行完成、产物大小与校验结果。成功任务应提供保存入口；保存后用独立 PDF 阅读器检查一页内容。
3. 断网重复上述流程，测试系统保存取消、重试、分享与任务清理。分享面板打开本身不视为接收成功。
4. 再使用截图中的 JPEG。当前子集是单图单页、baseline SOF0、8 位灰度/RGB、受支持 JFIF；最多 16 MP，拒绝 progressive、CMYK、EXIF/ICC 等未验证特征。扩展名相同不能保证符合子集；不自动移除元数据、重编码或改走其他路线。
5. 选择 DOCX/PPTX→PDF，应仍在提交前显示引擎未接入的原因。Release 中 JPEG 也应显示路线未开放；配置重载不会把 Release 变为 Debug。
6. 若失败，保留诊断记录中的阶段、错误码与 traceId，以及保存/独立打开的实际结果。不要把 UI 任务成功、目录展示或构建成功当成全链路验收。

当前验收结论：**JPEG→PDF 已具备代码层面的 Debug 测试资格，设备端验收待执行；DOCX→PDF、PPTX→PDF 尚未接入 Office 引擎。** 保留既有 Office 版本审核提案，不在本轮替换固定上游版本或用图片化/文本重排冒充 Office 保版式转换。
