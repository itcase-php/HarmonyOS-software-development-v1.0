# PDF 产物保存与分享（分阶段接入）

日期：2026-10-01。此阶段接入的是**已成功且已验证的 Native PDF 产物的交付操作**，不激活 JPEG→PDF 路线。`jpeg-pdf` 在共享矩阵及 NAPI 门禁中仍为 `planned`；因此当前应用正常流程尚不会出现可保存的真实 PDF，设备端到端验证仍待进行。

## A：保存 PDF

任务记录页只在 Native 结果为 `success`、校验为 `passed` 且包含 primary PDF 时显示“保存 PDF”。点击后，`DocumentViewPicker.save()` 让用户选择文件位置并返回文档 URI；ArkTS 打开该 URI 的写入描述符。新增的 `copyArtifactToFd(internalRef, fd, sha256, byteSize)` 在 Native 内解析不透明产物引用，复核已登记的摘要和字节数，按 64 KiB 写入，不把内部路径或整份 PDF 送到 ArkTS。复制和目标大小检查成功且描述符关闭后，任务会话内的 `ExportRecord.state` 才变为 `exported`。取消和失败分别记为 `cancelled` / `failed`，允许重试。一次写入失败可能在用户所选位置留下不完整文件，设备验收时需确认文件提供者的清理行为。

## B：SaveButton

未用于 PDF。华为的 `SaveButton` 面向媒体库图片、视频授权，不能给任意 PDF 颁发“下载”或“文档”目录的写入权。PDF 使用 A 的文档保存选择器。

## C：分享 PDF

任务记录页的“分享 PDF”先把已验证的产物复制到应用缓存目录，再将该副本的**应用文件 URI**和 PDF UTD `com.adobe.pdf` 交给 ShareKit `SharedData` / `ShareController.show()`。分享面板由系统处理接收应用的选择与文件访问。单独构造 `Want` 并传入 `internalRef` 不会让其他应用读取私有文件，因此实现采用官方的系统分享接口。面板成功打开仅表示分享已启动，不表示接收方已收到文件，也不改变 `ExportRecord` 为 `exported`。共享副本留在系统管理的应用缓存中供接收方读取；其回收和设备上的接收时序仍需验收。

## 边界与验证

- 不修改 `conversion-matrix.json`、image 引擎可用性、其他引擎、路线激活门禁，也不生成真机证据。
- `ExportRecord` 目前由会话 `TaskStore` 管理，随任务历史清理或应用退出消失；持久化的 `ConversionTask` / RDB 导出记录尚未实现。
- HAP 的 ArkTS 与 arm64-v8a/x86_64 Native 编译成功；主机 `production_runtime`、NAPI 导出与能力诊断等 10 项测试通过。Native 主机测试验证了产物复制后的 SHA-256 与大小。系统 Picker、分享面板、目标文件提供者和接收应用尚无真机验证。

依据：[DocumentViewPicker API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)、[SaveButton 所属媒体库范围](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/photoaccesshelper-overview-V13)、[ShareKit 文件分享示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/share-utd-video-V5)。
