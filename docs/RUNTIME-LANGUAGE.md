# 运行时中英文切换

状态：已实现并通过编译与宿主逻辑验证，待实际 Previewer/设备验收。开发基线为 `04e6886f5e1ada231970fc07430b4a51004f3826`。

后续用户审核优化：329 项资源改用一次建立的 Map 索引，PageHeader 直接展示已翻译标题，删除 FidelityPolicy 的三个旧标签方法。保护检查仅允许这次明确批准的策略清理，仍核对其余方法完整内容。语言切换机制保留。详见 [三项优化与 setLanguage 风险复核](LANGUAGE-OPTIMIZATION.md)。

## 本次开发前核对

已复核《软件开发1.0》《软件开发2.0》的最近交付记录、当前代码和 GitHub 草稿 PR #1。既有五页、18 种格式、43 条规划路线、保真度参数与演示调度继续保留。受限 JPEG→PDF 已进入内部 Native 构建，但 `jpeg-pdf` 仍为 `planned`，应用真实可用路线仍为 0。PDF 文档选择器保存与 ShareKit 分享已有代码；演示任务不会产生实际产物，因此不显示真实保存/分享入口。

## 使用方法

首页帮助中心 `?` 旁新增相同尺寸和配色的圆形按钮。中文界面显示 `EN`，英文界面显示 `中`，点击切换。

- 首次启动：中文系统选中文，其他系统语言选英文。
- 五页、组件、任务阶段/状态/历史结果、错误提示、确认内容和无障碍标签使用当前应用语言。
- 语言持久化与任务历史分开：语言选择跨启动保留；任务历史仍只属于当前会话。
- 用户文件名、路径、格式/路线 ID、MIME、协议错误码和字体名称属于数据，不改写。英文界面的 `中` 是切回中文的按钮标签。
- 演示默认名使用语言无关的 `example.ext`；用户输入的文件名在切换时保持原样。

## 实现与提示词修正

`common/LanguageManager.ets` 是语言来源，提供 `currentLanguage`、`currentLocale`、`getString()`、`toggle()` 和订阅 token。使用 `AppStorage` 通知 ArkUI，配合 `PersistentStorage.persistProp()` 保存选择。**AppStorage 本身不提供跨进程持久化。** 清空应用数据或卸载后会恢复首次启动默认值；Previewer 的持久化环境由 DevEco 决定。

有设备资源环境时，按语言缓存 `getOverrideResourceManager()`；创建时复制 `getOverrideConfiguration()` 并只覆盖 locale。Ability 在页面加载完成后调用 `ApplicationContext.setLanguage()`，满足 SDK 对窗口和页面就绪时机的要求。UI 的字符串仍通过 LanguageManager 读取，不依赖系统语言变化。

无宿主资源环境时，使用 `generated/LanguageCatalog.ets`。该文件由两份 `string.json` 生成，不手写另一套翻译。329 个资源键在 base/en_US 一一对应，参数占位符一致。资源修改后执行：

```powershell
node tools/generate-language-catalog.cjs
node tools/generate-language-catalog.cjs --check
```

使用 `@StorageLink('appLanguage')` 直接让界面字符串响应变化，替代提示词中每页缓存大量译文到 `@State` 的办法。已经缓存的选择器文字由 ConverterPage 订阅刷新，离开时注销；指南和报告使用 `@Watch` 重建展示数据。刷新不重新选路线、不重置降级同意、不改文件名、不重新提交任务。

`DemoTask.stage`、`resultLabel` 和 `taskStatusLabel()` 保存/返回资源键；`stageArgs`、`resultArgs` 在 clone 时复制。真实错误保存原协议码，显示时解析为当前语言提示。规划器只生成演示目标名称，由 UI 添加“演示名称，未生成文件”的说明；模拟报告的未检测限制也保存资源键。

Toast 和系统对话框在弹出时读取当前语言；预览器的内联确认在切换后重建，保持原待确认提交。已经弹出的系统 Toast/模态对话框由系统管理，不承诺原地更换其文字；正常 UI 中语言按钮位于首页，关闭对话框并返回首页后才能切换，后续弹出内容使用新语言。

将“真实转换引擎尚未接入”的旧提示修正为“真实转换路线尚未开放”，将指南“可执行路线”修正为“规划路线”。这些文案与当前 planned 门禁一致，未开放任何转换路线。

## 验证记录

| 检查 | 结果 |
| --- | --- |
| `entry@default assembleHap` | 成功，零编译错误；仍有已有 SDK/异常处理、重复名称和未签名警告 |
| `check-runtime-language.cjs` | 8 项通过；资源键/占位符、双向切换、SDK 资源缓存与调用时机、存储适配器重启、监听注销、任务快照、选择/同意保留、内联确认与受保护文件检查 |
| `check-interactions.cjs` | 15 项通过；五阶段检查改为解析资源键后断言，原队列/暂停/取消检查保持 |
| `check-refactor.cjs` | 12 项通过，Native 调度使用模拟导出 |
| `check-architecture.cjs` | 21 项通过 |
| `check-hypium-host.cjs` | 9 个 suite / 61 项通过；执行实际测试源的宿主适配器，非设备 Hypium |
| `check-input-management.cjs` / `check-fidelity.cjs` | 旧 NativeProtocol 哈希基线断言失败，详见下文；不报告为通过 |
| 编辑器 `builtin_check_editor_errors` | 当前工具环境未提供，未执行；编译成功不能冒充编辑器检查结果 |
| 实际 Previewer、真机、实际重启持久化 | 未执行，`hdc list targets` 返回 `[Empty]` |

两份历史脚本期望 NativeProtocol 的 SHA-256 为 `2a47dbe12f5cac8cc84654a27f6769d82cc3baea9d9b6c3751fd661e4db800e0`；本轮开始前 Git HEAD 已是 `a48889500afe6575c74a7b7ab0b1ef9dba852c2274ad335ecd5eb34b8adfdfa1`。本轮该文件没有 diff，未更新历史保护基线掩盖失败。新语言检查直接以本轮开始提交比对 Native/配置/权限等受保护文件，确认没有改动；现行架构、调度和 Hypium 宿主回归通过。历史基线的整合可另行审阅。

本轮日志及报告位于 `tests/generated/runtime-language-*`。宿主逻辑验证不代替实际 ArkUI 布局、点击、读屏或设备重启验证。

## 手动验收顺序

1. Previewer 打开 Index，点击 `EN`，核对标题、卡片、能力状态和帮助按钮读屏文字。
2. 按应用导航进入转换页、格式页、指南和历史页；分别确认章节、类别、纯文本格式名、参数说明和操作文字为英文。
3. 英文启动演示，在任务活动期间返回首页切换中文，再进入进度或历史。确认阶段/状态/完成结果同步变化，进度和任务身份不改变。
4. 在格式页保留查询和展开项，在转换页保留文件名、路线、质量、意图、最低等级和降级同意，再往返切换检查。
5. 用无扩展名的演示名触发错误，分别检查中文和英文提示；内联确认只在主动确认后开始任务。
6. 设备选择英文后退出并重启，核对语言保留；清空应用数据后核对系统默认值。
7. 根据屏幕宽度检查英文长文、按钮和无障碍朗读。系统文件选择器和分享面板的语言由系统组件管理。

## 审阅范围

具体既有代码改动见 [实施审阅说明](../spec/changes/runtime-language/implementation-review.md)。本轮按用户提供的语言需求改造展示和文字载体；后续激活路线、改原生协议、权限或保存/分享行为，需要另外审核。
