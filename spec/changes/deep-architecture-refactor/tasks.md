# 实现与验证任务

状态：implemented_pending_device_validation（2026-09-30）。用户批准记录见 implementation-review.md。

- [x] 错误工具、UUID、所有 FidelityPolicy switch 默认防御；step1 编译通过。
- [x] Registry/Native/Planner/Runner 实例及接口、扩展名/MIME 索引、Foundation race；step2 编译通过。
- [x] 文件服务/真实输入任务依赖注入、闲置 TTL、清理截止；step3 编译通过。
- [x] ServiceContainer 与 EntryAbility 生命周期、五类生成工厂、保持完整目录；step4 编译通过。
- [x] 运行/创建顺序队列索引、100 条预算、LRU、Native idle 等待；step5 编译通过。
- [x] 四个 @Observed VM 与协调器、可注入 UI 适配；step6 编译通过。
- [x] 六个组件、独立预览包装器、@ObjectLink、@Provide/@Consume、文件 LazyForEach；step7 编译通过。
- [x] 过期事件、错误兜底统一、必需 @Require、颜色资源原值迁移；step8 编译通过。
- [x] Picker 平台元数据依赖同一作用域、完整宿主回归和最终应用/测试包验证；记录见 architecture-validation-report.json。
- [ ] 连接设备执行系统 Picker/取消/隐藏/TTL、真机 Hypium、Previewer 点击、读屏与实际响应式刷新验收。
- [ ] 接入可用真实 Native 会话/引擎后执行端到端转换；本轮保留 C++ 占位。

独立编辑器诊断工具不可用，使用实际 Hvigor ArkTS 编译逐步骤检查。宿主检查中的 SDK/Native 使用适配器，不等于设备运行。历史输入阶段的原方法哈希保持为旧基线，架构重构按公共方法与行为回归验证；不覆盖旧哈希证明或声称实现字节不变。
