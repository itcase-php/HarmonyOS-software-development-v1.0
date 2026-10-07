# PDF 产物保存与分享（分阶段接入）

## 2026-10-07 保存与分享修复

用户在 `D:\HarmonyOS\harmonyOS` 的 Debug JPEG→PDF 转换成功后，选择保存位置仍失败，分享也失败。已修复：

- Native 原先把已提交的 PDF 留在输入工作区 `cache/workspace/<id>/outputs`。调度完成会删除输入会话及整个工作区，产物登记仍存在但文件已丢失。现将最终 PDF 原子提交到独立的 `cache/artifacts`；输入工作区只保留临时文件，最终产物由 `releaseArtifact` 或 `shutdown` 清理。输入授权和输出校验保持原有要求。
- `beginShare` 通知界面刷新，忙碌任务的保存/分享按钮会被移除；原分享调用仍以该按钮 ID 为锚点。设备复现 `SDK_401 / Parameter error`。现使用系统默认面板位置，不依赖已消失的按钮。
- 保存 URI 的打开模式增加 `CREATE`，兼容选择器返回尚未创建的目标；仍在复制、大小检查和关闭完成后才标记保存成功。新增诊断只记录阶段、系统数字错误码或受控 Native 原因，不记录 URI、路径和文件内容。

验证：修复前，两个 Native 回归用例均复现“input workspace cleanup removed owned PDF”；修复后 CTest 25/25、保存分享宿主 6/6、其余 12 组宿主检查通过。签名主应用与测试 HAP 构建并安装，设备 Hypium 65/65 通过；两张真实合成 JPEG 在注册释放、输入工作区删除之后仍能复制和校验 PDF。

另以 `-s class JpegDebugSmoke -s deliveryUi true` 运行可选交付测试，使用真实 Native 产物、真实文件 SDK 和系统 Picker/ShareKit，测试内的 TaskStore 子类仅隔离调度。实际保存到 Download，再通过系统选择器重新授权读取同一测试文件，1351 字节与验证过的分享副本逐字节一致，SHA-256 为 `0114650536ba75a354953318781f95a1d32a7bf6d20c4730f41765e5d664dd3c`。独立 PDF 解析确认一页 8×8 pt、JPEG 字节不变，Poppler 渲染与样例像素一致。实际观察到分享面板显示 `converted.pdf`、1.35 KB 及应用入口，随后取消，未发送给联系人。交付测试 2/2 通过。

证据见 [交付验证记录](../tests/generated/jpeg-delivery-validation.json)、[宿主检查](../tests/generated/artifact-delivery-host-report.json) 和 [独立 PDF 检查](../tests/generated/jpeg-delivery-pdf-validation.json)。独立 PDF 检查脚本自身不操作 Picker/ShareKit，其对应字段仅描述该脚本范围；系统交付证据在交付验证记录中。

边界：尚未验证接收应用实际收取文件、全部文件提供者、首次断网与 Release。任务历史仍是会话状态。修复前已经被清理的旧任务 PDF 无法恢复，需重新转换。下方 2026-10-01 内容为历史阶段记录。

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
