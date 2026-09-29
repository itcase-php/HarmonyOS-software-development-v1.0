# 迁移结果与实现边界

更新日期：2026-09-29。本文描述当前实际工程；V1.0 方案和七份专题文档继续描述目标架构，不能据此认定所有功能已经实现。最新修复与验证见[格式目录恢复与回归验证](格式目录恢复与回归验证.md)；上一轮审计记录见[审计改进与验证说明](审计改进与验证说明.md)。操作步骤继续参考《交互功能与使用说明》及《保真度控制与参数管道》。

## 已迁入并接入工程

1.ArkTS 层：页面、组件、模型、格式注册、转换规划、任务管理、NativeBridge

2.C++ 层：NAPI 入口、转换器接口、错误码、IR 结构、资源限制、保真校验、PDF/Office/Media/Image/OCR 引擎占位

3.共享配置：formats.json、conversion-matrix.json

4.文档：架构、转换矩阵、AI 编程规则、隐私、错误码、保真策略、上架检查清单

5.测试：格式矩阵和 DRM 类格式阻断测试

以上固定条目保留原文和顺序。各条目中的目标能力没有全部实现，本次完成程度如下。

| 范围 | 实际状态 |
| --- | --- |
| 页面/组件 | 保留五页及原交互；FidelitySettingsCard 使用单个 FidelitySettingsVM，保留三事件和内部展开状态，组合 QualitySelector；转换页用一个 @State fidelityVM 发布选择和展示快照。格式浏览器、保真度、路线提示、报告及主要读屏标签使用 base/en_US 资源；其他旧页面未全面国际化。首页/格式浏览器/转换页/指南立即使用完整目录，资源或 Native 检测失败仍保留演示；真实文件选择/结果预览仍待引擎接入 |
| 模型 | DemoTask.clone() 集中复制全部任务字段及报告；FidelitySettingsVM.clone() 复制完整面板状态及选项；TaskRuntime 支持独立测试时钟。Native 协议/类型声明和 C++ DTO/IConverter 保持原样 |
| 格式注册 | 完整的 18 格式、43 规划路线从原 shared JSON 生成，启动和预览即刻可查询，资源加载失败不会缩减。rawfile 核对 SHA-256、schema/config 及数量后原子替换；并发调用共享加载，失败/五秒超时可重试，迟到数据不覆盖缓存，查询返回深复制。真实可用路径还要求资源校验成功、配置 available 状态和 Native 发布证据 |
| 转换规划/任务管理 | 保留参数快照、2/3.5/6 秒活动时长、单并发 FIFO 与暂停/恢复/取消；enqueue 返回 queued/0%，首次 50ms 回调、后续 200ms 递归 setTimeout，advance 有 try/finally 防重入和时钟回拨保护。enqueueNative/NativeTaskRunner 沿用 NativeBridge.execute；保护门禁、进度序号、取消后迟到结果与释放仍接线。当前真实路线为 0；Native 暂停、授权文件、持久化和后台服务未实现 |
| NativeBridge | 保留动态 so 导入、13 API 与 isNativeAvailable；原失败后重试已存在，本轮补共享加载尝试身份检查，防止旧拒绝清空新重试。参数/结果校验保留，能力查询五秒超时；预览器需要应用资源上下文才能加载配置，缺少 Native 可继续演示，缺少资源则显示错误及重试 |
| C++ | 正式 entry 模块注册、异步 NAPI 调度、异常边界、五领域 unavailable 适配器及可生成注册表已接入；保留原 add 示例导出，业务不使用它 |
| IR/资源/保真 | demo commit 生成模拟报告；native 仅从 ConvertResult.fidelity 读取并校验意图/等级/指标和证据，不生成示例填补缺失报告。两者共用深复制工具，界面按 mode 显示。流式 IR、资源监控、真实输出校验器尚未实现 |
| 配置更新 | 构建生成、运行时打包 JSON 解码/哈希验证及首次加载的原子缓存已实现。配置数字签名、热更新、回滚和新版本快照切换仍待开发；摘要校验不等于签名验证 |
| 测试 | 15 项交互、13 项保真、12 项原重构、55 项 Hypium 源码和 16 项审计及目录回归，共 111 项宿主检查通过。8 个 Hypium 套件注册到本地/ohosTest，源码通过宿主适配器执行；应用/测试包编译和 HAP 配置核验通过。目录回归覆盖 18×18 格式组合和 15,552 组质量/意图/最低等级选择。实际设备 Hypium、Previewer、读屏和真实引擎仍未执行 |

## Native API 的当前行为

| API | 当前行为 |
| --- | --- |
| getCapabilities | 校验请求/schema/configVersion/sessionId 类型，异步返回 schemaVersion、布尔 offlineOnly、编译 ABI、configVersion；engines/routes 为空，因此可执行路径为 0 |
| initializeSession / registerWorkspace / probeInputs | 异步拒绝，UNSUPPORTED_FEATURE，MIGRATED_CONTRACT_NOT_IMPLEMENTED；未建立授权会话、工作目录或深层文件探测 |
| execute | 在基础字段校验后异步返回 failed / ENGINE_MISSING；无输出、validation=not_evaluated，不读写输入文件 |
| cancel / pause / resume | 对不存在的任务异步返回 not_found；不是已实现暂停或任务控制 |
| subscribeProgress / unsubscribeProgress | 当前无执行引擎；前者抛 ENGINE_MISSING，后者返回 false |
| releaseTask / releaseArtifact / shutdown | 当前无持久句柄，异步清理空操作；正式引擎接入时必须补齐所有权与活动任务同步 |

能力查询用固定的非授权 bootstrap 标识，只用于工程检查，不能作为转换会话凭据。引擎缺失结果中的 nativePeakBytes/tempPeakBytes=0 表示当前没有引擎工作区/文件分配，未实现进程内存测量，不可用于性能验收。

NAPI 调度不在 worker 中访问 JS 对象；异常在入口和 completion 捕获，正常可用环境中拒绝原 Promise 并释放异步工作句柄。环境销毁/内存完全耗尽时 NAPI 操作只可尽力清理。C++ 异常捕获不能防御第三方解析器的越界或系统级信号；未来仍需模糊测试、资源限制与引擎隔离评估。

## 保留与调整

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

先实现并验证文件授权与受控副本、Native 完整解码及路径/资源/保护校验，再用图片→PDF 建立首条真实链路。替换 `engines/image` / `engines/pdf` 适配器，补齐输出验证、工作目录清理、Native 引用释放与性能测量。绑定层的能力查询和 execute 目前是明确的占位逻辑，首次启用真实转换前需完成调度器接线；引擎注册表已经可由配置生成，后续新增引擎无需手写格式分支。

只有真实转换、独立输出验证和发布证据通过后，才将对应配置 route 改为 available，并由 Native 公布相同能力。DRM/加密/签名深层阻断测试必须在该门禁之前完成；当前扩展名黑名单查询不是内容保护检测器。接入后禁止返回无效“成功”。
