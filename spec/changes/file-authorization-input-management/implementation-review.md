# 接入差异审核

2026-09-29。已读取上传提示词、proposal/design/tasks，以及实际 ArkTS、Native 协议和 API 26 SDK 声明。

## 建议采用的实现

1. 新增 SessionModels、FormatDetector、FileAuthorizationService。格式检测遍历当前 FormatRegistry，覆盖全部原 18 种格式及其别名/MIME，不添加 tasks.md 中尚未注册的 DOC、EPUB、视频等格式，也不减少已有格式或路线。
2. 使用 @kit.CoreFileKit 的 DocumentViewPicker，通过 EntryAbility 注入 Stage 上下文；不用静态服务中的 getContext(this) 或 require。缺少上下文或系统能力时返回不可用并保留完整演示。
3. 使用 Picker 的临时只读 URI 授权，不申请 FILE_ACCESS_MANAGER。选中后立即按文件描述符读取并拷入受控目录，防止 URI 被当成普通路径。大小同时按实际 stat 和拷贝字节检查，单文件 100MB、会话总量 300MB；分块处理，不一次分配整个大文件。
4. 保留 NativeProtocol、NativeBridge、NativeTaskRunner 和全部 C++ 实现。新增真实提交入口调用实际 initializeSession/registerWorkspace API，成功后复用 enqueueNative/execute 路径及原能力、保护、保真门禁。INVALID_INPUT 不在原 ErrorCode 中，文件超限使用现有 RESOURCE_LIMIT_EXCEEDED + FILE_TOO_LARGE。
5. 当前 C++ initializeSession/registerWorkspace 是 Unsupported 占位，所以真实文件提交会如实产生 mode=native 的 failed 记录，提示原生会话/引擎尚未接入；不会伪造授权成功、绕过门禁或回退成演示完成。本次不声称已经到达真实引擎执行阶段。
6. 当前 NativeTaskRunner 只接受单文件。允许选择/管理最多 10 个文件，真实转换提交先明确要求一个文件；保留原单文件路线约束。多文件执行需要另行设计与审核，不修改现有门禁。

## 已实现功能的保护

原 18 格式/43 规划路线、ConversionPlanner、演示 enqueue 与 50ms/200ms 调度、质量/意图/最低等级、确认和模拟报告保留。ConverterPage 仅新增真实文件选择、信息、移除和独立确认分支；未选择真实文件时继续调用原方法。TaskStore 新增真实输入提交及文件所有权清理入口，不改原演示方法。EntryAbility 仅新增上下文注入与受控临时目录清理。

## 需要用户审核的差异

用户已于 2026-09-29 回复：“同意兼容方案，保留现有功能和 C++ 占位（推荐）”。批准范围包括不申请 FILE_ACCESS_MANAGER、使用现有 API/错误码、单文件真实提交、占位失败如实展示。实现与验收状态见 tasks.md。

补实现 Native 会话/工作区或多文件执行超出本次“纯 ArkTS、不修改 C++”规格，后续需要单独审核具体设计。

依据：OpenHarmony [Picker 文件授权说明](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/select-user-file.md)、本机 API 26 CoreFileKit 声明及现有 NativeProtocol/NativeTaskRunner。具体文件拷贝、取消和临时目录释放通过可注入平台适配器测试；真机/预览点击结果单独记录。
