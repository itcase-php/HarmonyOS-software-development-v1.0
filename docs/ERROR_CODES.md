# 错误码：开发与用户版

来源：本交付包主方案，2026-09-28。设计稿，非已实现/已验收声明。本文由 tools/assemble-docs.cjs 生成，修改主方案后重新生成。

### 错误码文档：开发技术版与用户简化版

下表包含稳定字符串码、触发与排查及用户动作；Native 显式整数映射见 converter.h。reason 用白名单细化，UI 文案本地化，兼容旧码不复用数值/含义。

| 错误码 | 触发/开发排查 | 用户提示与动作 | 自动重试 |
| --- | --- | --- | --- |
| UNSUPPORTED_FORMAT | 无 operation/方向/输入子集；查配置与真实识别 | 此文件与目标组合暂不支持，选择可用目标 | 否 |
| ENGINE_MISSING | engine/codec/模型未链接/加载；查构建/ABI/probe | 当前安装版本不具备此转换能力 | 否；配置通常应预先隐藏 |
| PASSWORD_REQUIRED | 兼容协议保留；后续授权密码流程才使用 | 文件需要授权密码；首版保护阻断走PERMISSION_DENIED | 否 |
| PASSWORD_INVALID | 后续输入授权密码错误；不记密码 | 密码不正确，请核对 | 否 |
| FILE_CORRUPTED | 受控解析失败/截断/非法结构；查样例和检测器 | 文件损坏或无法安全读取，保留原件重试来源 | 否 |
| RESOURCE_LIMIT_EXCEEDED | bytes/pages/pixels/zip/native-memory超硬预算 | 文件超出当前处理限制，可分批或调整已说明参数 | 仅准入等待；已超硬限不重试 |
| OCR_LOW_CONFIDENCE | 低置信项；通常warning，拒收策略才失败 | 识别内容需核对，请查看标记区域 | 否 |
| OUTPUT_VALIDATION_FAILED | 输出重开/结构/保真门禁失败；查证据与引擎 | 结果未通过检查，未保存为成功文件 | 仅批准备用引擎、无安全问题时 |
| CONVERSION_CANCELLED | 协作取消已确认且清理完成 | 已取消，原件保留 | 否 |
| INVALID_REQUEST | 必填/enum/finite/范围/重复任务/option白名单 | 参数无效，请修改或重新创建任务 | 否 |
| PERMISSION_DENIED | 外部URI撤权或reason=DRM_BLOCKED/ENCRYPTED_BLOCKED/SIGNATURE_BLOCKED/PROTECTION_UNKNOWN | 文件授权失效，或受保护文件不支持转换；区分原因 | 否，安全失败不降级 |
| INPUT_NOT_FOUND | 输入被删除/授权引用不可重开 | 找不到输入文件，请重新选择 | 否 |
| STORAGE_FULL | staging/manifest/导出ENOSPC | 存储不足，请清理空间；保留已完成应用结果 | 用户处理后 |
| CONVERSION_TIMEOUT | 到deadline并发出受控终止；不宣称已强杀 | 转换超时，原件保留，可分批处理 | 默认否 |
| TASK_INTERRUPTED | 系统终止/进程崩溃恢复识别 | 上次任务中断，可重新执行 | 用户选择后 |
| FONT_MISSING | 关键字体/字形不可用，查授权字体包/映射 | 缺少所需字体，查看替代或保真限制 | 仅已批准fallback |
| UNSUPPORTED_FEATURE | 输入关键元素或暂停能力未实现 | 此项功能暂不可用或无法保留该元素 | 否 |
| INTERNAL_ERROR | 未分类异常，保留脱敏trace/本地符号版本 | 转换发生内部错误，原件保留 | 否；防止崩溃循环 |
| PROTOCOL_INCOMPATIBLE | 三端schema主版本/插件ABI协议不一致 | 当前模块版本不匹配，请更新正式版本 | 否 |
| CONFIG_INVALID | schema/引用/签名/防回退失败 | 配置未通过检查，继续使用原配置 | 否 |
| ABI_UNSUPPORTED | 当前设备目标库缺失/不兼容 | 当前设备不支持该引擎 | 否 |
| TASK_BUSY | 活动任务被release/重复开始/不合法控制 | 任务正在处理，请等待当前操作结束 | 不重复提交 |
| IO_ERROR | errno/短读短写/提供者失败；保留细化reason | 文件读写失败，请核对文件与保存位置 | transient_io最多一次 |

日志结构：timestampUtc、monotonicElapsedMs、level、traceId、匿名taskId/attemptId、module、stage、code/reason、engine/version、配置hash、资源统计、脱敏stackFrameIds。堆栈地址/符号可用于开发定位，但不能附带用户路径、内存正文或密码；用户主动导出前复检。对外文案不暴露第三方原始 exception message。
