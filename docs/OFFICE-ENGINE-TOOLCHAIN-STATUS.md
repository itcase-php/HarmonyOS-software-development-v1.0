# Office 引擎前置验证与 Native 报告修复

日期：2026-10-06。执行用户批准的三路线计划；本文件为阶段交付，不是三路线完成声明。

后续 2026-10-07 的 JPEG Debug 门禁修复、实际构建与待设备验收项目见 [修复记录](JPEG-DEBUG-ROUTE-REPAIR.md)。下文记录前阶段状态，Office 版本提案仍待审核。

## 既有功能修改清单

| 修改 | 修复后的行为 | 审核范围 |
| --- | --- | --- |
| production_napi 结果序列化 | completion 回调调用单独的序列化函数，输出已有协议字段 | 原异步执行、队列、会话和文件授权流程未重写 |
| warnings / fidelity | 保留引擎实际生成的警告与报告、测量状态、证据和人工复核标记 | 没有报告时不制造报告或 achievedTier |
| 数字可选字段 | 保留值为 0 的页数、页索引和指标 | 不使用真假值判断数值是否存在 |
| error | 保留 Native Status 的 module、stage、traceId、messageKey、retryable、detailKey | 不把所有执行失败覆盖成 preparing 或固定 traceId |
| 回归 | 先复现 warnings 丢失与诊断覆盖，再修复；模拟 NAPI 检查实际返回字段 | 不是转换引擎或设备验收 |
| 工具链探针 | 独立编译 OHOS arm64/x86_64；核对固定上游编译器前置要求 | 不接工厂、不宣告转换能力 |

路线状态、Release 门禁、字体策略、资源限制、五页、18 种格式、43 条路线、语言、演示和保存/分享流程均未调整。本次没有更换批准的 LibreOffice 提交。当地签名配置、旧工作区的 FormatDetector/ImageConverter 改动、用户文档、原始设备日志和二进制不进入 PR。

## 实际验证

| 层次 | 本轮结果 | 边界 |
| --- | --- | --- |
| Native 宿主 | MSVC/Ninja CTest 23/23，通过新增报告回归 | 实际生产序列化代码 + 测试专用 NAPI 模型；不是手机执行 |
| 真机入口/架构宿主 | check-device-entry 11 项、check-architecture 21 项通过 | 不替代系统 Picker 或转换验收 |
| 主应用 | Hvigor Debug / Release 构建通过，arm64-v8a、x86_64 | 编译/签名成功不等于引擎转换 |
| ohosTest | 签名 Debug HAP 构建通过 | 设备执行单列 |
| Linux API26 工具链 | 两种 ABI 最小 C++ 库编译、链接、ELF 头检查通过 | 未进行 Stage 加载、Office 排版、内存/包体测量 |
| 设备 | API24 手机，主应用/测试包安装成功；解锁后本轮 Hypium 63/63，通过 | 包括真实 ResourceManager 回归；不执行三路线真实转换。首次锁屏失败保留在本地记录 |
| 固定 LibreOffice | autogen/config.sub 拒绝 OHOS；独立编译器前置检查发现 Clang15 < 所需18 | 完整目标构建未完成，DOCX/PPTX 加载/导出未执行 |

当前三路线验收状态：DOCX→PDF、PPTX→PDF 均未接入真实 Office 后端；JPEG→PDF 的现有生产 Runtime 宿主测试通过，但本轮正式入口、断网、保存、独立打开、分享验收未完成。三条路线都不计最终完成。

## Office 选型提案（待用户审核）

原提交的源码版本为 27.2.0.0.alpha0+；它要求 Clang18，而用户提供的匹配 API26 官方 Native 工具链是 Clang15.0.4。更换 Linux 包没有消除这个版本差异。复现方式、摘要和实际构建参数在 [探针说明](../prototypes/office-harmony/README.md)。

1. **优先提案：改用官方维护版本 LibreOffice 26.2.6.2 开始 OHOS 移植验证。** 该标签的配置要求至少 Clang12，近期官方已发布 26.2.6。仍须重新固定提交/归档摘要、处理 OHOS 平台分支、排版依赖、运行资源、双 ABI 和真机加载。仅满足编译器版本前置条件，未证明兼容。先前提出的 25.8.2.2 方案被这个较新候选取代，尚未实际切换。
2. **保留原提交，单独验证更新编译器或回移兼容补丁。** 必须确认新编译器生成的 OHOS 目标、SDK/sysroot、libc++ 和链接依赖兼容；完整构建、加载、资源与输出验收仍不可省略。不能用桌面 Linux/Android 二进制，也不能简单删除 Clang18 检查。该方案扩大工具链/源码适配范围，需要提交具体版本与补丁后审核。
3. **商业鸿蒙离线 Office SDK。** 先索取目标平台、DOCX/PPTX→PDF、离线字体、禁止网络、资源上限、取消和再分发证据及试用库，跑同一参考样例再决定。公开存在鸿蒙 PDF SDK 不等于存在鸿蒙 Office 排版能力；当前福昕 Office 转换公开平台列表只有 Windows/Linux。本轮未采购或联系厂商。

本机 API26 的 `@hms.filemanagement.filepreview.d.ts` 声明 Office 文件预览；`@hms.officeservice.pdfservice.d.ts` 提供 PDF 服务。核对的公开声明中没有找到 DOCX/PPTX 排版导出 PDF 的接口，不能据此取消 Office 引擎移植。华为终端应用具备的文件转换功能也不能被当成第三方应用可调用、首次断网可用的 SDK。

用户尚未批准更换引擎版本；后续依赖此决定的移植暂停在当前前置检查。已有授权覆盖的 Native 报告修复、宿主检查、Hvigor 构建及阶段 GitHub 同步继续执行。未将结构重排或图片化作为原保版式路线的实现。

所有候选都需比较固定 Word/PowerPoint 导出的参考 PDF、中文字体、页面、表格、图片与关键数值。没有证据能够保证任意 Office 文档转换后完全无差异。

## 官方来源

- [原固定 configure.ac](https://github.com/LibreOffice/core/blob/6804c10b45d52787c1e865e3ad192d7dfc7d4862/configure.ac)。
- [26.2.6.2 configure.ac](https://github.com/LibreOffice/core/blob/libreoffice-26.2.6.2/configure.ac)；[26.2.6 发布公告](https://blog.documentfoundation.org/blog/2026/09/04/libreoffice-26-2-6/)。
- [LibreOfficeKit 接口](https://docs.libreoffice.org/libreofficekit.html)。
- [福昕 Office/PDF 转换平台表](https://developers.foxit.com/documents/product-overview/conversion-sdk.html)；[鸿蒙 PDF SDK 开发指南](https://developers.foxitsoftware.cn/SDKdoc/Foxit_PDF_SDK_HarmoryOS_DeveloperGuide_CN.pdf)。
- [官方 NAPI 异步任务模式](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/napi/use-napi-asynchronous-task.md)。
