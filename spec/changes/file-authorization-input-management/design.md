# 技术设计：文件授权与输入管理

本文件已按 2026-09-29 用户批准的兼容方案修正；审核记录见 implementation-review.md。代码完成、宿主及编译验证通过，设备/预览验收仍待执行。

## 架构决策

### AD-1：使用 DocumentViewPicker 而非 photoAccessHelper

**决策**：通过 `@kit.CoreFileKit` 静态导入 `picker.DocumentViewPicker`，由 EntryAbility 注入 Stage 上下文。
**理由**：文档转换场景的输入是 PDF/DOCX/JPEG 等文档文件，不是相册媒体。DocumentViewPicker 支持任意文件类型，且不需要申请相册权限。
**替代方案**：photoAccessHelper 仅适用于图片/视频，无法选择 PDF/DOCX。

### AD-2：沙箱拷贝策略 — 受控副本 + 大小限制

**决策**：用户选择文件后，将文件拷贝到应用沙箱 `cacheDir/workspace/<sessionId>/inputs/` 目录，拷贝前校验文件大小不超过 ResourceBudget.maxInputBytes。
**理由**：Native 层只能访问沙箱文件；直接操作 URI 有权限过期风险。受控副本确保 Native 层有稳定的文件路径。
**约束**：拷贝完成后计算 SHA-256，与 Native 层共享校验值。

### AD-3：Session/Workspace 生命周期与 TaskStore 对齐

**决策**：Session 在用户选择文件时创建，在任务完成/取消/应用退出时销毁。Workspace 目录在 Session 创建时建立，在 Session 销毁时递归删除。
**理由**：避免残留临时文件占用空间；与 TaskStore 现有的任务生命周期管理对齐。

### AD-4：预览器降级 — FileAuthorizationService.isAvailable()

**决策**：新增 `FileAuthorizationService.isAvailable()` 静态方法，在预览器下返回 false。ConverterPage 根据此值决定显示"选择文件"按钮还是"演示模式"提示。
**理由**：与 NativeBridge.isNativeAvailable() 保持一致的降级模式。

### AD-5：格式检测 — 扩展名 + MIME 双重推断

**决策**：遍历完整 FormatRegistry，扩展名优先、MIME 回退，不一致记录警告。实际 Picker 只返回 URI；适配器通过描述符取得大小、FileUri 取得名称，MIME 使用注册提示值。
**理由**：不能虚构 Picker 的 MIME 字段；推断结果不能代替 Native 完整内容和保护探测。检测保留全部原 18 格式及别名。

## 新增模块

### 1. FileAuthorizationService（services/FileAuthorizationService.ets）

```
class FileAuthorizationService {
  static isAvailable(): boolean
  static async pickDocuments(maxCount: number): Promise<PickedFile[]>
  static async copyToSandbox(file: PickedFile, sessionId: string): Promise<AuthorizedFile>
  static async createSession(): Promise<SessionContext>
  static async destroySession(sessionId: string): Promise<void>
  static getWorkspaceRoot(): string
}
```

### 2. SessionContext（models/SessionModels.ets）

```
interface SessionContext {
  sessionId: string
  workspaceRef: string    // 沙箱内工作目录路径
  createdAt: number
  inputFiles: AuthorizedFile[]
}

interface AuthorizedFile {
  fileId: string          // 随机内部名
  originalName: string
  relativePath: string    // workspace 内相对路径
  byteSize: number
  sha256: string
  detectedFormatId: string
  mimeType: string
}

interface PickedFile {
  uri: string
  fileName: string
  fileSize: number
  mimeType: string
}
```

### 3. FormatDetector（services/FormatDetector.ets）

```
class FormatDetector {
  static detect(fileName: string, mimeType: string): string  // 返回 formatId
  static detectByExtension(fileName: string): string | null
  static detectByMime(mimeType: string): string | null
}
```

## 修改模块

### ConverterPage.ets
- 新增"选择文件"按钮（FileAuthorizationService.isAvailable() 为 true 时显示）
- 文件选择后显示文件信息卡片（文件名、大小、检测格式）
- 创建 Session/Workspace，将 AuthorizedFile 传入任务提交
- isAvailable() 为 false 时保持现有演示模式

### TaskStore.ets
- 新增 submitTask()：接受 AuthorizedFile[] + SessionContext，当前真实执行要求一个文件
- 演示模式（无授权文件）保持现有行为不变
- 真实模式调用现有 initializeSession/registerWorkspace，取得真实 Native 句柄后复用 prepare/enqueueNative；初始化五秒超时，迟到注册释放

### NativeBridge.ets
- 保持 NativeBridge、NativeProtocol、NativeTaskRunner 和全部 C++ 不变
- initializeSession/registerWorkspace 仍为 Unsupported 占位，如实形成 failed 真实记录；没有真实转换成功

## 数据流

```
用户点击"选择文件"
  → DocumentViewPicker.select()
  → PickedFile[] 返回
  → FormatDetector.detect() 推断格式
  → FileAuthorizationService.createSession() 创建 Session
  → FileAuthorizationService.copyToSandbox() 拷贝到沙箱
  → AuthorizedFile[] 生成
  → ConverterPage 显示文件信息
  → 用户点击"开始转换"
  → TaskStore.submitTask(authorizedFiles, session, route, fidelity)
  → NativeBridge.initializeSession(SessionInit)
  → 当前占位拒绝 MIGRATED_CONTRACT_NOT_IMPLEMENTED → failed 真实任务及临时目录清理
  → 将来会话可用时 registerWorkspace → NativeTaskRunner.prepare → enqueueNative
  → 原能力/发布证据/输入保护门禁通过后，NativeTaskRunner.run → NativeBridge.execute
```

## 预览器降级路径

```
FileAuthorizationService.isAvailable() === false
  → ConverterPage 不显示"选择文件"按钮
  → 显示"预览模式：文件选择功能在真机可用"提示
  → 保持现有演示流程不变
```

## 权限配置

按用户批准方案，module.json5 保持不变，不申请 FILE_ACCESS_MANAGER。DocumentViewPicker 提供临时只读 URI 授权，立即以描述符复制到受控目录。依据见 [OpenHarmony 文档](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/select-user-file.md)及本机 API 26 声明。

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| Picker URI 权限过期 | 拷贝到沙箱后不再依赖原始 URI |
| 大文件拷贝阻塞 UI | 异步 256 KiB 分块、部分写入处理，显示复制状态，单文件 100 MiB/会话 300 MiB |
| 沙箱空间不足 | 拷贝前检查可用空间 |
| 格式检测错误 | 注册目录推断，源格式与已授权输入必须一致；实际内容仍需 Native 探测 |
| 预览器 Picker 不可用 | isAvailable() 降级到演示模式 |
