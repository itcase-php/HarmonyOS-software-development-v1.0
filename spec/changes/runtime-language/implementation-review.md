# 运行时语言切换：实施审阅说明

开发依据：用户提供的运行时中英文切换提示词。状态为 `implemented_pending_user_review_and_device_validation`。本轮代码提交到已有草稿 PR #1，供用户审核，不合并或发布。

后续用户审核已明确要求资源索引、PageHeader 重复翻译和 FidelityPolicy 旧标签方法三项整理，已按此范围实施；以下清单保留原语言开发阶段记录。最新策略变化仅删除三个旧展示方法，业务方法由限定差异检查保护；setLanguage 机制未修改。最新审阅边界和设备风险见 [三项优化说明](../../../docs/LANGUAGE-OPTIMIZATION.md)。

## 已开发内容的具体调整

| 文件/范围 | 调整内容 | 对既有行为的影响 |
| --- | --- | --- |
| 五个 pages 与文本组件 | 硬编码文字迁入双语资源，绑定 appLanguage，首页增加 EN/中按钮；Native 进度报告显式传入 task.mode，避免默认显示演示报告标题 | 页面导航和操作回调继续沿用；展示语言可切换，报告标题与任务模式一致 |
| EntryAbility | 绑定资源上下文；页面加载成功后设置应用语言 | 增加语言配置，不改启动服务和 Native 初始化 |
| ArkUiConverterUi / PreviewConverterUi | 文字读取改为 LanguageManager；预览缺少宿主时读取生成资源 | FidelityText 文件保留原样；UI port 的文字参数兼容 ResourceStr |
| InteractionModels / TaskStore | stage/resultLabel 与状态显示函数改用资源键，动态参数分开并复制 | 调度时间、进度、FIFO、任务 ID、暂停/取消和导出状态转移保留；消费者需在 UI 解析文字键 |
| ConversionPlanner / DemoFidelityReport | 演示目标名称与演示说明分开；报告限制使用资源键 | 不改变路线规划与报告指标值；未生成文件的说明在 UI 显示 |
| FormatSelectionVM / ConverterCoordinator | 仅刷新选择器和确认展示文字 | 保留路线选择、质量、用户文件名和降级同意，不自动提交 |
| ConversionStatusVM / UiFeedback / ErrorHandler | 错误显示存资源键，弹出时读取语言 | 原错误归一化、日志去敏、重试流程继续沿用 |
| base/en_US string.json | 同步 329 个资源键，修正“未接入”和“可执行”的过期说法 | 对齐当前 planned 状态，不改变真实能力 |
| tests / docs / README、READMES | 新增语言检查，现有五阶段断言适配键表示，更新状态与验收步骤 | 历史 NativeProtocol 哈希失败如实记录，未改历史保护基线 |

用户提示词已明确要求以上语言改造，本轮范围没有包含其他业务改造。请结合 PR 的本轮提交审核这些展示/模型表示变更；如需调整实现方式，可继续在草稿分支修改。

## 受保护内容核对

以下内容相对 `04e6886f5e1ada231970fc07430b4a51004f3826` 没有变更，并在新检查中自动核对：全部 C++/NAPI、共享矩阵与 rawfile、NativeBridge、NativeTaskRunner、ArtifactDelivery、NativeProtocol、FidelityPolicy、FidelityText、RegistryData、module.json5、build-profile.json5 和历史迁移归档。没有增加页面路由或权限。

JPEG→PDF 的计划状态和执行门禁保持。演示记录不会显示真实保存按钮；语言开发可在无真机的预览环境进行，而真实 PDF 转换/保存仍需独立设备和发布验收。

验证结果、失败说明和人工检查清单见 [运行时语言说明](../../../docs/RUNTIME-LANGUAGE.md)。
