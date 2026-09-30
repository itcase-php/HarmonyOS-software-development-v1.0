# 架构与所有权

## 状态与依赖

ConverterPage 只持有四个 @State VM。FormatSelectionVM 管目录/选择/路线；FidelityConfigVM 继承 @Observed FidelitySettingsVM；FileAuthorizationVM 管 Picker/副本/会话；ConversionStatusVM 管任务订阅和错误。ConverterCoordinator 冻结确认快照并装配生命周期。UIContext 通过 ConverterUiPort 适配，不进入核心测试。

SourceFormatSelector、TargetFormatSelector、FidelityConfigPanel、AuthorizedFilePanel、ConversionProgressPanel、ConversionErrorBanner 使用 @ObjectLink；各文件的 @Preview 包装器提供合法 VM。进度组件 @Consume 根页 @Provide 的 services，单页隐藏不销毁任务服务。FidelitySettingsVM.clone 接口保留用于显式快照，页面不再用它刷新。

EntryAbility.onCreate 建立 ServiceContainer，每个作用域拥有 registry/native/files/tasks；服务接口和构造函数允许隔离的测试替身。旧静态 API 仅作为兼容委托，旧页面继续可调用。EntryAbility.onDestroy 只清理其捕获作用域。

## 性能与预算

生成器按 PDF/Office/Text/Image/Media 创建分类工厂，数据只在查询时实例化；完整查询按原配置顺序返回 18/43。rawfile 校验和原子安装保留。扩展名/MIME Map 跟随实例 catalogueVersion 失效，保持扩展名优先规则。

调度仅推进 runningTask，并从创建顺序队列取下一项；暂停/恢复不抢占正在运行任务。100 条历史保护活动任务；timings 随结束清理；Native 结果有同规模 LRU 上限，历史淘汰释放对应输出。通知仍提供完整的有界历史快照，未声称所有 UI 通知为 O(1)。Native 退出通过共享 idle Promise 等待，取消后的迟到成功不得复活。

Select 保留完整 options；授权卡片使用 List/LazyForEach 和稳定 fileId。颜色原值移入 color.json，必需 text/report 属性添加 @Require。

## 清理与错误

闲置且未认领、无复制操作的会话默认 30 分钟 TTL，可配置/禁用；复制活动刷新期限，任务认领停止过期。过期事件清空对应页面草稿并提示重新选择。普通隐藏清理未提交输入；系统 Picker 临时隐藏例外；提交 finally 清空页面引用，仅在未移交任务服务时销毁其会话。

FoundationViewModel 使用 Promise.race 和 finally 清理截止定时器。清理超过五秒报告超时，底层未结束时保留管理器所有权，供完成或重试；race 不取消 NAPI/文件 Promise。

ErrorHandler 统一安全 instanceof 检查、代码/traceId 日志及可注入报告钩子；不自动上传用户信息。ArkTS 类型守卫使用 instanceof 和布尔辅助函数，不使用其不支持的 TypeScript 类型谓词。SDK Object/JSON/NAPI 边界仍需类型声明，但先校验对象/字段/协议或来源，不把强制转换当作验证。UUID 不可用的预览环境用毫秒+单调序列保底，避免异常构造递归调用错误工具。
