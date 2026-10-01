# 迁移结果与实现边界

更新日期：2026-10-01。本文描述当前工程；V1.0 方案和专题文档描述目标，不能认定全部实现。用户已批准[分阶段接入范围](../spec/changes/jpeg-pdf-production/approval-request.md)，JPEG→PDF 的受限核心进入生产 Native 构建，但路线暂不激活；当前阶段结果见[验证记录](VALIDATION-JPEG-PDF-PRODUCTION.md)。原目录恢复及审计记录保留作历史溯源。

## 已迁入并接入工程

1.ArkTS 层：页面、组件、模型、格式注册、转换规划、任务管理、NativeBridge

2.C++ 层：NAPI 入口、转换器接口、错误码、IR 结构、资源限制、保真校验、PDF/Office/Media/Image/OCR 引擎占位

3.共享配置：formats.json、conversion-matrix.json

4.文档：架构、转换矩阵、AI 编程规则、隐私、错误码、保真策略、上架检查清单

5.测试：格式矩阵和 DRM 类格式阻断测试

以上固定条目保留原文和顺序。各条目中的目标能力没有全部实现，本次完成程度如下。

| 范围 | 实际状态 |
| --- | --- |
| 页面/组件 | 保留五页及原交互；ConverterPage 79 行、四个观察 VM、六个独立组件；FidelitySettingsVM 使用 @Observed/@ObjectLink，页面不再 clone 刷新。首页/历史页使用 ServiceContainer 的作用域实例。原国际化、读屏、完整目录与演示保持；系统 Picker 与实际 ArkUI 刷新待设备/预览验收 |
| 模型 | DemoTask.clone() 继续隔离任务及报告；FidelitySettingsVM.clone() 作为旧兼容接口保留。会话、目录、请求、结果改用逐字段自有副本，替代 12 处 JSON 序列化复制，类型字段覆盖和嵌套隔离有宿主测试。NativeProtocol、C++ DTO/IConverter 保持原样 |
| 文件输入 | 新增 SessionModels、FormatDetector、CoreFileKit 平台适配器、FileAuthorizationService 和 AuthorizedInputTask；Picker 授权、256 KiB 分块副本、100/300 MiB 预算、SHA-256、串行复制、幂等清理与单文件真实确认/提交。C++ 会话/工作区和受限 JPEG 完整探测已接入，设备验收待执行 |
| 格式注册 | 完整的 18 格式、43 规划路线从原 shared JSON 生成，启动和预览即刻可查询，资源加载失败不会缩减。rawfile 核对 SHA-256、schema/config 及数量后原子替换；并发调用共享加载，失败/五秒超时可重试，迟到数据不覆盖缓存，查询返回深复制。真实可用路径还要求资源校验成功、配置 available 状态和 Native 发布证据 |
| 转换规划/任务管理 | 保留参数快照、2/3.5/6 秒活动时长、单并发 FIFO 与暂停/恢复/取消；enqueue 返回 queued/0%，首次 50ms 回调、后续 200ms 递归 setTimeout，advance 有 try/finally 防重入和时钟回拨保护。enqueueNative/NativeTaskRunner 沿用 NativeBridge.execute；保护门禁、进度序号、取消后迟到结果与释放仍接线。当前真实路线为 0；Native 暂停、持久化和后台服务未实现 |
| NativeBridge | 保留动态 so 导入、13 API 与 isNativeAvailable；原失败后重试已存在，审计补共享加载尝试身份检查，防止旧拒绝清空新重试。参数/结果校验保留，能力查询五秒超时；预览器缺少 Native 模块或应用资源上下文仍可使用完整目录及演示，检测或资源校验失败不会启用真实路线 |
| C++ | 正式 entry 模块注册、异步 NAPI 调度；会话、工作区、受限 JPEG 深层探测、转换候选、输出结构验证、取消和清理已实现。image 工厂替换为实验实现，其他四类引擎仍占位。NAPI 按生成的 `planned` 状态拒绝执行，能力查询提供规划诊断而不发布可用引擎。主机 MSVC CTest 22 项通过，其中新增生产能力诊断 NAPI mock 检查；原 mock NAPI 8 项仍仅检查历史占位分支 |
| JPEG→PDF 核心 | 独立原型的固定块流、受限 JPEG 解码、图片 IR 与 PDF Writer 已编入双 ABI `libentry.so`；15 项外部 PDF 解析/渲染集成检查及新增运行时宿主检查通过。当前仅支持单张 8 位 Baseline SOF0 灰度或三分量 JPEG；路线仍为 `planned`，未发布 releaseEvidenceId；详见[阶段验证](VALIDATION-JPEG-PDF-PRODUCTION.md) |
| IR/资源/保真 | demo commit 生成模拟报告；native 仅从 ConvertResult.fidelity 读取并校验意图/等级/指标和证据，不生成示例填补缺失报告。两者共用深复制工具，界面按 mode 显示。JPEG→PDF 有专用流与固定结构输出校验；通用流式 IR、完整资源监控和真实保真报告尚未实现 |
| 配置更新 | 构建生成、运行时打包 JSON 解码/哈希验证及首次加载的原子缓存已实现。配置数字签名、热更新、回滚和新版本快照切换仍待开发；摘要校验不等于签名验证 |
| 测试 | ArkTS 宿主脚本全部通过；MSVC CTest 22/22、独立原型 15 项 PDF 集成检查通过。生产运行时单页 PDF 经 pypdf 严格解析、嵌入 JPEG 字节核对和 Poppler 渲染；应用/ohosTest 编译及双 ABI HAP 核验通过。实际设备 Hypium、Picker、Previewer、读屏和应用真实引擎仍未执行 |

## Native API 的当前行为

| API | 当前行为 |
| --- | --- |
| getCapabilities | 校验请求/schema/configVersion/sessionId 类型，异步返回 schemaVersion、布尔 offlineOnly、编译 ABI、configVersion；若实验 image 工厂可自述，则 routes 包含 `jpeg-pdf` 的 `planned` 诊断和实际解码/编码子集，engines 仍为空。可执行路径为 0；工厂缺失或自述失败时诊断数组为空 |
| initializeSession / registerWorkspace / probeInputs | 异步建立会话、核验工作区；受限 JPEG 经过完整解码、字节数与 SHA-256 核对后才返回确定探测，否则为 unknown。设备路径及权限仍待验收 |
| execute | NAPI 因 `jpeg-pdf=planned` 异步返回 failed / ENGINE_MISSING；内部 C++ 运行时能执行受限转换并提交经结构校验的 PDF，用于宿主验证。尚无应用可用路线 |
| cancel / pause / resume | 已注册任务的 cancel 设取消标志，pause/resume 返回 unsupported；不存在任务返回 not_found |
| subscribeProgress / unsubscribeProgress | 订阅 token 与清理已接线；路线未激活时不发真实执行进度 |
| releaseTask / releaseArtifact / shutdown | 已接入任务取消、引用释放和产物清理；设备并发与文件系统竞态仍待验收 |

能力查询用固定的非授权 bootstrap 标识，只用于工程检查，不能作为转换会话凭据。引擎缺失结果中的 nativePeakBytes/tempPeakBytes=0 表示当前没有引擎工作区/文件分配，未实现进程内存测量，不可用于性能验收。

NAPI 调度不在 worker 中访问 JS 对象；异常在入口和 completion 捕获，正常可用环境中拒绝原 Promise 并释放异步工作句柄。环境销毁/内存完全耗尽时 NAPI 操作只可尽力清理。C++ 异常捕获不能防御第三方解析器的越界或系统级信号；未来仍需模糊测试、资源限制与引擎隔离评估。

## 保留与调整

本次 P0 输入管理前快照：`D:/HarmonyOS/migration-backups/harmonyOS-before-input-management-20260929-213740`。用户批准兼容方案后仅新增输入模块和接线；22 个 TaskStore 原方法及规划器/Native/完整目录基线一致，C++、权限声明和签名配置未变。真机/Previewer 验收未执行，SDD 状态为 implemented_pending_device_validation。

本轮审计修改前的完整跟踪文件快照：`D:/HarmonyOS/migration-backups/harmonyOS-before-audit-20260929-194609`。已演进 RegistryTypes、RegistryData、NativeBridge 和 FeatureGuide；NativeProtocol、C++ converter.h、五页路由、原始格式/路线 JSON 与迁移归档仍原样保留。以下段落是此前各轮的历史记录，不能作为本轮未改文件清单。

组件与调度优化前快照保存在 `D:/HarmonyOS/migration-backups/harmonyOS-before-refactor-20260929-110433`。本轮没有改变 NativeProtocol、RegistryTypes、RegistryData、NativeBridge、converter.h、FeatureGuide 或 main_pages.json。Native 预留入口要求已有授权 session/workspace/PreparedInput，不能根据演示文件名伪造这些数据；当前可用路径仍为 0。详见《组件与任务调度优化说明》。

本轮保真度改动前的 12 个文件保存在 `D:/HarmonyOS/migration-backups/harmonyOS-before-fidelity-20260929-093220`，基线见 `tests/generated/fidelity-baseline.json`。NativeProtocol、RegistryTypes、RegistryData、NativeBridge、converter.h，以及用户已有 FeatureGuide 和五页路由配置均保持字节一致。所有保真类型复用现有 NativeProtocol；新增的是演示参数载体、校验策略和模拟报告，不包含 Native.execute 接线。

最低期望等级是筛选门禁，质量模式不会提升路线的规划等级，也不会改变用户指定意图。例如实际配置中的 PDF→DOCX 是兼容保真/结构化重建，不能照提示词示例改为极致保真。达不到最低等级时禁止开始，不自动降级。

2026-09-29 的修改前快照另外保存于 `D:/HarmonyOS/migration-backups/harmonyOS-before-interactions-20260929`。当前工程中的 NativeBridge 在此次任务开始时已经由用户侧改为动态导入；本次沿用该改动并修复弱化的资源/路径/结果检查。根 build-profile.json5 在此次任务开始时已无 product.signingConfig，本次没有修改根签名配置或制造证书，构建仍提示 No signingConfig found，产物仍未签名。

交互任务模型 DemoTask 与原 Native ConversionTask/ConvertResult 分开。演示完成状态为 completed，带 mode=demo，界面和结果名称均标明未生成文件，不能升级格式配置状态或产生真实转换成功证据。

原交付文件全部按 SHA-256 留存于 `docs/migration-source`，逐文件映射见 MIGRATION_MANIFEST.json。原 `outputs` 未改写。修改前的 46 个工程文件另存于 `D:/HarmonyOS/migration-backups/harmonyOS-before-outputs-migration-20260928`；模板图标和未调整的工程文件保留。

业务依赖继续是 `libentry.so`，NAPI 模块名继续是 `entry`，没有复制一个不匹配模板的 Node 模块注册方式。`.d.ts` 不能导入 `.ets`，因此生成 Native 内部 Protocol.d.ts，并校验它与 ArkTS 模型完全等价。

AppScope bundleName、版本号、应用名称、已有 phone 设备声明、SDK/API 26、BiSheng 工具链和原测试未改变；项目当前最低兼容仍是 API 26，尚不能宣称覆盖更早的 HarmonyOS NEXT 正式版本。后续需建立最低系统版本测试后再调整 compatibleSdkVersion。

备份模板仍保留，但 backup_config.json 的 allowToBackupRestore 改为 false，避免文档数据默认参与系统备份。未增加网络或广域存储权限。该设置不是整机无网络证明；离线验收仍应检查依赖和实际运行。

## 接入真实引擎的顺序

ArkTS 文件授权与受控副本已完成宿主/编译验证。JPEG→PDF 的受限核心已接入生产 C++、内部运行时和 NAPI；Native 会话/工作区、完整受限解码、输出结构校验及引用释放已有主机验证。路线仍为 `planned`，能力查询仅报告规划诊断，NAPI 执行被拦截。激活前还需设备 Picker/授权路径与权限验收、并发和取消竞态测试、文件系统路径竞态加固、真实输出导出、资源测量、合法签名及发布证据审核。其余引擎和通用转换仍待实现。

只有真实转换、独立输出验证和发布证据通过后，才将对应配置 route 改为 available，并由 Native 公布相同能力。DRM/加密/签名深层阻断测试必须在该门禁之前完成；当前扩展名黑名单查询不是内容保护检测器。接入后禁止返回无效“成功”。
