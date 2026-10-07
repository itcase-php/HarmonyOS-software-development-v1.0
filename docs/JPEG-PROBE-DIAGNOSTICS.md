# JPEG 输入检查的错误归因修复

日期：2026-10-07。修复用户在 `D:\HarmonyOS\harmonyOS` 导入 JPG/JPEG 时收到笼统“真实格式或保护状态未通过检查”的问题。

## 原因与修改

原生探测把解码失败、尚不支持的 JPEG 特征、资源超限和副本校验失败都返回为 unknown protection。任务调度随后统一报告 `NATIVE_INPUT_NOT_VERIFIED`，界面因此错误地引导用户检查文件保护状态。用户没有提供同一图片，本轮不能确定其图片触发的是哪一条限制。

- C 探测器保留内部失败类别，区分附加 APP 数据段、编码类型、颜色模式、JFIF 密度、受限文件头和像素上限。修复文件头检查成功后错误码被清零、后续解码错误可能丢失的问题。
- Runtime 将这些失败变成既有 BridgeProblem，并区分内存预算、损坏数据、文件大小和摘要不一致。
- 真机进一步复现：异步 NAPI 桥又把具体原因改成 `NATIVE_WORK_REJECTED`。改为由异步工作对象持有原因字符串，直到 Promise 拒绝交付完毕。
- 双语界面按具体原因显示提示。未知检查失败的兜底提示不再断言文件损坏或受保护。NativeProtocol 字段、支持的 JPEG 子集、资源上限、保护检查与 Debug/Release 门禁均未扩展。

## 验证

先写失败回归，再修复：原生 CTest 从 23/24 变为 24/24；手机上的原因传递测试先复现 63/64，再达到 64/64。真实 NativeBridge 已验证 APP1 数据段、损坏 JPEG、摘要不一致的具体错误原因。

12 组相关宿主检查通过，其中 Debug 路线与错误提示检查 5 项。Debug 主应用和 ohosTest 均重新构建、安装，测试结束已启动主应用。受限基线样例仍通过实际转换、产物复制和释放；设备生成 PDF 经独立解析与渲染验证，JPEG 字节不变、平均像素差为 0。

详见 [本轮验证报告](../tests/generated/jpeg-probe-validation.json) 与 [PDF 验证报告](../tests/generated/jpeg-probe-pdf-validation.json)。复现沿用 `JPEG-DEBUG-LOCAL-SYNC.md` 的构建与设备测试命令，PDF 检查可指定本轮日志：

```text
python tests/check-jpeg-device-pdf.py --log tmp/jpeg-probe-smoke-hilog.log --report tests/generated/jpeg-probe-pdf-validation.json
```

本轮修复的是错误归因和提示。EXIF/ICC、渐进编码、CMYK 等兼容性仍待实现，不能视为一般手机照片已经通过转换验收。未用用户图片验收，未执行系统 Picker、保存/分享界面、首次断网或 Release 验收。Word/PPT 及其余路线的状态未改变。
