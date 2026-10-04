# 语言实现三项优化与风险复核

开发基线：`99392620a143113b486339ae50db790941ce6d0d`。本轮按用户审核意见执行，顺序为资源索引 → PageHeader → 旧标签方法清理。

## 实施结果

| 优先级 | 文件 | 改动与可行性 |
| --- | --- | --- |
| 中 | LanguageManager.ets | 当前目录实际为 329 项。模块加载时用循环建立一次 `Map<string, LanguageEntry>`；getString 使用 get，formatName/stage/detail 使用 has，渲染路径不再逐条 find/some |
| 低 | PageHeader.ets | 已核对三个调用方均传入译好的字符串。title/subtitle 改为 string 并直接展示；返回按钮继续响应语言切换，避免重复查找和把标题意外当作资源键 |
| 低 | FidelityPolicy.ets | 删除 tierLabel/intentLabel/qualityLabel 和未用的 Intent 导入。应用代码没有调用；架构测试有动态调用，已同步移除对三个被删方法的断言 |

索引仅持有已有 LanguageEntry 对象引用，不复制译文，也不通过 map() 创建临时二元组数组。索引占用额外 O(n) 引用空间，以换取平均 O(1) 查找；本轮没有测量或宣称 HAP、堆内存和帧率的具体改善。329 项双语资源、生成目录和资源管理器缓存保留，避免删掉预览器所需的回退翻译。

FidelityPolicy 的 tierRank、durationMs、isQualityMode、validate 内容保留；没有让纯业务策略依赖 LanguageManager/SDK。现有保护检查允许用户明确批准的三个方法删除，并以旧提交 AST 移除这三个方法后对比整个策略文件，仍禁止其他策略修改。

## 已实现内容的改动边界

上述 PageHeader 参数类型收窄和三个旧方法删除属于本次明确要求的代码整理。当前全部应用调用方已适配，编译和现行回归用于确认没有遗漏。后续使用 PageHeader 时，调用方应先解析标题/副标题，不直接传 Resource。

本轮没有修改语言持久化、语言切换通知、ApplicationContext.setLanguage、覆盖资源管理器、五页行为、任务调度、C++/NAPI、转换矩阵、权限、保存分享、FidelityText 或生成译文。JPEG→PDF 仍 planned。

开始时已有一处 FormatDetector.ets 删除未用导入的工作区改动，本轮保留在本地并排除提交，没有修改或代替用户提交。

## setLanguage 风险复核

`ApplicationContext.setLanguage()` 设置的是**应用语言**，不是设备全局语言，也不等同于需要系统应用身份的 System API。主线程和窗口/页面加载时机仍须满足接口要求。参见 [OpenHarmony 官方 ApplicationContext 文档](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-ability-kit/js-apis-inner-application-applicationContext.md)；兼容信息同时核对了本机 API 26 SDK 声明。

| 风险 | 当前证据与处理 | 真机验收 |
| --- | --- | --- |
| 应用配置与覆盖资源管理器共同作用 | 两者读取同一个 appLanguage，分别使用对应的 zh-CN/en-US 与 zh_CN/en_US；覆盖管理器的 locale 显式指定。代码和宿主模拟未发现不同语言目标，但不能据此证明设备上绝无刷新竞态 | 连续往返切换，进入五页核对普通资源与覆盖资源一致；任务期间切换检查闪烁/重复刷新 |
| 配置回调干扰 | 当前工程没有实现 onConfigurationUpdate 或 environment 订阅来反写 appLanguage，不存在已接入的回写循环。官方文档还注明：设置应用语言后，系统语言变化的环境订阅回调受到限制；不能笼统假设所有配置回调都会触发或都不会触发 | 在应用选择英文后修改设备语言，确认应用选择、持久化和任务状态不被覆盖；观察配置刷新和 Ability 生命周期 |
| API 兼容性 | setLanguage 自 API 11 提供，覆盖资源管理器自 API 12 提供；当前工程 compatible/target SDK 均为 26，未修改最低版本。宿主测试覆盖加载时机与资源缓存，不能代替具体设备 API 行为 | 在项目实际支持的 API 26 设备上检查首次启动、切换、后台恢复和重启 |

**本轮保留既有语言机制。** 如要删除 setLanguage，仅依靠覆盖资源管理器，需另外审核应用普通资源、系统组件/导航和页面配置刷新是否受到影响，再修改及验收；本轮没有擅自执行这一机制变更。

## 验证

- `tests/check-runtime-language.cjs`：8 项通过，包含语言往返、持久化适配器、资源管理器缓存/就绪时机、任务状态/名称与同意保留、内联确认、受保护文件及限定的策略删除检查。
- `tests/check-architecture.cjs`：21 项通过。
- `tests/check-hypium-host.cjs`：9 个 suite / 61 项通过；不是设备 Hypium。
- `entry@default assembleHap`：成功，零编译错误；已有警告和未签名状态继续保留。日志见 `tests/generated/language-optimization-build.log`。
- 真实 Previewer/设备、实际重启和配置回调验收尚未执行，不能以宿主测试证明设备 API 行为。

此前记录的两个旧 NativeProtocol 哈希断言失败保留在 [运行时语言说明](RUNTIME-LANGUAGE.md)，本轮没有修改那些历史基线。
