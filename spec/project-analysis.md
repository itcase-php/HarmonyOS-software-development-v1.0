# 项目架构与进度分析

批准范围内输入管理与架构拆分已实现，宿主与编译验证通过；设备/预览验收仍待执行。本轮异常、副本与索引兼容优化已验证，205 项 ArkTS 宿主检查、13 项 C++/mock NAPI 测试通过。用户批准的独立 JPEG→PDF 原型另有 4 项 C++ 和 15 项外部 PDF 集成检查通过；生产 Native 真实链路仍等待另审。输入、架构与原生就绪变更分别见 changes/file-authorization-input-management/tasks.md、changes/deep-architecture-refactor/tasks.md、changes/native-readiness-and-copy-safety/tasks.md。

更新日期：2026-09-30

## 技术栈

- **上层**：ArkTS / ArkUI（Stage 模型，API 26）
- **底层**：C++ / NAPI（libentry.so，动态导入）
- **构建**：hvigor + DevEco Studio
- **配置**：rawfile JSON（SHA-256 校验）+ 编译期生成元数据

## 工程结构

```
entry/src/main/ets/
├── pages/          # 5 页：Index, FormatBrowser, ConverterPage, TaskHistory, FeatureGuide
├── components/      # ActionCard, FoundationCard, StatusBadge, FormatTag, PageHeader, QualitySelector, FidelityReportCard, FidelitySettingsCard
├── viewmodel/       # FoundationViewModel, TaskStore, ConversionPlanner, FidelityPolicy, DemoFidelityReport, NativeFidelityReport, FidelitySettingsVM
├── services/        # NativeBridge, FormatRegistry, RawfileResources, NativeTaskRunner, FormatDetector, FileAuthorizationService, HarmonyFilePlatform, AuthorizedInputTask
├── models/          # NativeProtocol, RegistryTypes, InteractionModels, SessionModels 与显式快照副本
├── generated/       # RegistryData, ErrorCatalog
├── common/          # BridgeError, UiFeedback, RegistryUi, FidelityText
└── entryability/    # EntryAbility

entry/src/main/cpp/
├── napi/            # native_bridge.cpp（13 API，异步调度）
├── core/            # converter.h, engine_registry, missing_converter
├── engines/         # pdf, office, media, image, ocr（全部为 MissingConverter 占位）
├── generated/       # registry_metadata.h
└── tests/           # 独立主机 CTest；mock NAPI 不入设备包
```

## 已完成功能

| 模块 | 状态 | 说明 |
|------|------|------|
| 页面导航 | ✅ 完成 | 5 页路由 + 页面跳转 + 返回处理 |
| 格式浏览 | ✅ 完成 | 18 格式、43 路线、分类/搜索/详情展开 |
| 转换演示流程 | ✅ 完成 | 格式选择→路线筛选→保真度设置→确认→五阶段进度→结果 |
| 任务管理 | ✅ 完成 | FIFO 单并发、暂停/恢复/取消、历史清理、2/3.5/6s 模拟时长 |
| 保真度控制 | ✅ 完成 | QualitySelector 三档、FidelityPolicy 校验、DemoFidelityReport 模拟报告 |
| NativeBridge | ✅ 完成 | 动态 so 导入、13 API、isNativeAvailable()、预览器降级 |
| 配置校验 | ✅ 完成 | rawfile SHA-256 验证、原子替换、并发安全 |
| 预览器兼容 | 🔶 逻辑与编译验证 | rawfile 不可用时保留完整目录；无文件上下文时入口不可用，尚未实际点击 Previewer |
| 错误体系 | ✅ 完成 | BridgeError + ErrorCatalog + 超时/重试 |
| 国际化 | 🔶 部分 | 保真度/格式浏览器已覆盖，旧页面未全面国际化 |

## 未完成功能（按优先级排序）

| 优先级 | 模块 | 当前状态 | 影响 |
|--------|------|----------|------|
| **P0** | 文件授权与输入管理 | 🔶 实现及宿主/编译完成，设备待验收 | Picker、受控副本/摘要、卡片/移除、真实提交入口；Native 会话/工作区仍占位 |
| **P0** | 应用真实转换引擎 | ❌ 全部占位；仅有隔离主机原型 | 0 条真实可用路线，应用不生成转换文件 |
| **P1** | 输出验证与导出 | ❌ 未开始 | 无法保存转换结果 |
| **P1** | 任务持久化 | ❌ 未开始 | 退出应用任务丢失 |
| **P2** | 后台调度服务 | ❌ 未开始 | 长任务无法后台执行 |
| **P2** | 真机测试验证 | ❌ 未开始 | 无设备验收证据 |
| **P3** | 配置签名/热更新 | ❌ 未开始 | 摘要校验≠签名验证 |
| **P4** | 翻译功能（用户构想） | ❌ 未开始 | 转 PDF/Word 时内置翻译，暂不紧急 |

## C++ 引擎现状

所有 5 个引擎均为 `MissingConverter` 占位：

```cpp
// pdf_converter.cpp
std::unique_ptr<IConverter> CreatePdfConverter() {
    return std::make_unique<MissingConverter>("pdf");
}
// image_converter.cpp, office_converter.cpp, media_converter.cpp, ocr_converter.cpp 同理
```

NativeBridge.getCapabilities() 返回 engines=[] routes=[]，因此 availableRoutes=0。

## 测试覆盖

- 原有 173 项 + 32 项副本/索引 = **205 项 ArkTS 宿主检查通过**；13 项 C++/mock NAPI CTest、隔离原型 4 项 C++ 和 15 项 PDF 集成检查另外通过
- 覆盖 18×18 格式组合 + 15,552 组质量/意图/等级选择
- **缺失**：真机 Hypium、Previewer UI、读屏、真实引擎端到端

## 架构关键约束

1. **NativeBridge 是唯一跨层入口**，不绕过直接调 NAPI
2. **演示与真实分离**：DemoTask ≠ Native ConversionTask，演示不伪造真实成功
3. **保真度门禁**：达不到最低等级禁止开始，不自动降级
4. **配置原子性**：rawfile 校验通过后才原子替换，失败保留旧缓存
5. **预览器降级**：rawfile/Native 不可用时自动使用内置演示数据，不阻塞用户

## 当前架构重构（2026-09-30）

ConverterPage 以四个观察 VM 装配六个职责组件，参数和 @ObjectLink 共享观察对象，services 由根页 @Provide、进度组件 @Consume。EntryAbility 创建隔离的服务容器，静态 API 为兼容委托。目录分五类工厂按查询实例化；全量仍为 18/43。FormatDetector 使用实例版本索引。调度维护 runningTask/创建顺序队列，结果 LRU 跟随 100 条历史预算。文件 VM 管 Picker 例外、finally 清理和闲置会话过期；原生输入所有权继续由服务保持。

对应新增目录/文件：components 六个 Panel/Selector/Banner、viewmodel 四个 VM/ConverterCoordinator/ConverterUiPort、services ServiceContainer/ServiceContracts/TaskDependencies、generated/catalogue 五个工厂、common ErrorHandler/Deadline/ArkUiConverterUi。验证见 tests/generated/architecture-validation-report.json；原 C++ 会话与五类引擎仍占位，无真实可用路线。
