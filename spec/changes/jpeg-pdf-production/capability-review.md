# 能力矩阵诊断与路线门禁复核

日期：2026-10-01。用户选择保持 `jpeg-pdf=planned`，先完善诊断。本次不激活转换路线。

## 提示词中需要修正的判断

1. `ImageConverter.Describe().available=false` 与实验实现状态一致。代码已链接并可在内部运行时调用，不等于经过设备和发布验收的对外可用引擎。把版本直接改为 `1.0.0` 会掩盖实验阶段。
2. `EngineStamp.buildHash` 在 ArkTS `NativeTaskRunner.run()` 中必须匹配 64 位小写十六进制。建议的 `dct-jpeg-pdf-v1` 不符合协议，也不是真实构建摘要；`scaffold`/`not-linked` 不是 ArkTS 的判断条件。
3. `RouteCapability` 的协议字段是 `routeId`、`availability`、`reason`、`supportsPause`、`supportsCheckpoint`、`decoderIds`、`encoderIds`、`inputSubsetId`、`validationProfileId`、可选 `releaseEvidenceId`。`from`、`to`、`operation`、`pathMode`、`intent`、`fidelityTier` 属于共享转换矩阵的路线定义，不属于 Native 能力 DTO。
4. `FormatRegistry.availableRoutes()` 要求共享路线 `available`、Native 路线 `available`、非空 `releaseEvidenceId`，并要求资源校验已完成。当前共享矩阵仍为 `planned`。此外，生产 NAPI `execute` 会按生成的 `kJpegPdfRouteStatus` 拒绝执行。这些门禁不会因 image 自述或 Native 诊断路线而解除。

## 本次调整

`getCapabilities` 在生产构建中读取 `CreateConverter("image")->Describe()`。若工厂及自述可用，就从生成的路线 ID/校验配置与实际解码、编码、输入子集 ID 形成一条 `availability=planned` 的诊断记录。`engines` 保持空数组，路线没有发布证据；工厂缺失、自述失败或配置不再是 `planned` 时诊断数组保持空。ArkTS、共享矩阵、生成元数据和其他引擎未修改。

生产版能力查询通过单独的主机 NAPI mock 测试：检查 13 个导出、异步结果、`planned` 路线、受限子集 ID、空 engines、无 `releaseEvidenceId`，以及不在能力 DTO 中添加 `from` 等共享配置字段。MSVC CTest 22/22 与双 ABI 应用、ohosTest 编译通过；`hdc` 无设备，真机响应仍待验收。

诊断记录只帮助定位受限能力与发布闸门，不能使 `NativeTaskRunner.run()` 通过路线匹配。后续激活仍需按[阶段验证记录](../../../docs/VALIDATION-JPEG-PDF-PRODUCTION.md)补齐设备、并发、安全和发布证据，再提交用户审核。
