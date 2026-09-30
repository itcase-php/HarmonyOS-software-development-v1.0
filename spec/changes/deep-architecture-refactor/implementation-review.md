# 深度架构重构：实施与兼容差异审核

日期：2026-09-30。基线 c3a7e414dc5ddf2015564d56ffb1ba3f911c8b10；完整跟踪文件已备份到 D:/HarmonyOS/migration-backups/harmonyOS-before-architecture-refactor-20260930。

## 核对结果

当前是 18 格式、43 规划路线，不是 50+ 格式。TaskStore 已有 100 条历史上限和活动任务保护；advanceOnce 已跳过非 running 任务，timings 会在结束/取消时删除，Native 输出在历史淘汰时释放。因此本轮改进以可注入依赖、明确预算、运行/队列索引和释放验证为主，不能据审阅文字误判为完全无保护。

## 已授权的具体实施

拆成用户指定的六个组件，页面仅装配与 UI 上下文适配。建立四类 @Observed VM，@ObjectLink 传递对象、@Provide/@Consume 提供服务，保留既有 FidelitySettingsVM.clone 公共接口但不再用于页面刷新。组件预览采用每个文件独立的 @Preview 包装组件，给必需的 @ObjectLink 提供有效 VM。

创建实例 Registry/Native/文件服务、ServiceContainer、服务接口和注入构造函数；旧 static API 保留兼容委托。保真外部接口、五页路由/main_pages.json、原格式/路线定义、演示时长/FIFO/暂停/恢复/确认/报告和 C++ 占位保持。错误处理统一、UUID traceId、switch 防御分支、@Require 和资源颜色均按提示词实施。

## 需要批准的兼容处理

| 提示词条目 | 建议落地方式及理由 |
| --- | --- |
| AbilityStage.aboutToAppear | SDK 没有该生命周期。ServiceContainer 在实际 EntryAbility.onCreate 初始化，根页提供依赖；文件服务需要 UIAbilityContext。保留现有模块配置，避免为无效回调新增启动结构。 |
| Maps 上限例如 50、自动淘汰 | 保留已通过的 100 条历史上限。完成结果按访问顺序管理；不删除活动任务 timing，不在用户仍能查看报告时提前释放输出。预算跟随既有历史淘汰，增设容量断言和清理检查。 |
| TaskStore.aboutToDisappear 停表 | TaskStore 不是 ArkUI 组件。页面离开解绑观察者；队列继续运行，保留已有跨页查看任务的行为。无可运行任务或 Ability 销毁时停表；不把共享调度器绑定到单页销毁。 |
| 全部原生 API 先检查 isNativeAvailable | so 调用使用 NativeBridge 内部懒加载、实例可用性和异常保护。Picker/文件 SDK 独立检测自身能力，不因 C++ 引擎不可用禁用选文件；纯 isNativeAvailable 初始 false 也不能阻止首次 so 加载。 |
| Registry 分类懒加载 | 生成各分类的工厂模块，按查询实例化；完整列表查询仍返回原 18/43，离线/预览/校验失败不缩减。转换页 Select 需要完整 options，不能改成只显示当前分类。 |
| ConverterPage 格式列表 LazyForEach | 当前格式由 Select(options) 展示，不是 ForEach；Select 无法包 LazyForEach。保留选择器，文件卡片在适用的 List 中按需渲染。无需为 18 个选项改动既有交互。 |
| Promise.race 避免底层 pending | 保留五秒截止、定时器 finally 清理、尝试身份及迟到结果保护。Promise.race 本身不取消 NAPI/文件 Promise，不将它称为底层资源释放；活动调用保持原取消与所有权约束。 |
| onPageHide 清理文件、自动 TTL | 路由离开清理未提交副本；系统 Picker 尚在选择时保留其调用。未提交且无复制操作的闲置会话采用可配置 30 分钟 TTL，提示过期；已认领/运行输入不自动删除。清理超时只报告并保留所有权供重试，不删除仍被调用读取的文件。 |

独立 builtin_check_editor_errors 工具在当前工具列表不可用。每个步骤使用实际 Hvigor ArkTS 编译及相关宿主验证，分别留下记录；不把编译称为编辑器/Previewer/真机验收。完成后同步原公共 GitHub 仓库。

上述建议是依据用户“必要调整先审核”提出；批准后才接入相应行为。独立的错误工具、索引及模型可先实现和测试。

用户已回复“同意上述兼容方案（推荐）”；以上兼容处理于 2026-09-30 获批。
