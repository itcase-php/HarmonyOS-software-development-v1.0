# JPEG→PDF 生产链路接入：现有功能调整审核

日期：2026-10-01。基线：`7fdfb81`。本文件记录实施前审核材料；截至创建时，生产 Native 仍为占位，真实可用路线为 0。

审核结果：用户批准“分阶段接入，暂不激活路线”。本阶段按批准范围实施生产 C++、NAPI、构建、测试和文档；`jpeg-pdf` 保持 `planned`，Native 不发布可用能力。设备与发布证据齐备后再单独审核激活。实施结果见[阶段验证记录](../../../docs/VALIDATION-JPEG-PDF-PRODUCTION.md)。

## 已核对的基线

- ArkTS 的 `NativeBridge`、`AuthorizedInputTask`、`NativeTaskRunner` 已有 13 API、授权副本、提交门禁和清理流程。本阶段保留其手写源码与预览演示行为。
- C++ 的 `initializeSession`、`registerWorkspace`、`probeInputs` 拒绝调用；`execute` 返回 `ENGINE_MISSING`；image 工厂返回 `MissingConverter`。用户上一阶段明确选择保持这些生产占位，先完成独立 JPEG→PDF 原型，因此替换占位行为需要本次审核。
- `shared/format-registry/conversion-matrix.json` 的 `jpeg-pdf` 仍是 `planned`。`FormatRegistry.availableRoutes()` 同时要求共享路线 `available`、Native 路线 `available` 和非空发布证据。现有 `check-design`、`check-migration`、`check-audit` 还断言所有路线都为 `planned`。
- 独立原型只支持单张 8 位 Baseline SOF0、灰度或三分量 JPEG，并拒绝渐进式、EXIF/XMP/ICC、CMYK、尾随数据等。原型验证不等于设备发布证据。

## 请求审核的现有代码调整

| 范围 | 拟议调整 | 影响与保持的边界 |
| --- | --- | --- |
| `entry/src/main/cpp/napi/native_bridge.cpp` | 将会话、工作区、探测、执行、进度、控制和释放的占位逻辑替换为真实实现；在入口线程完成 NAPI 解析和 JS 回调，在 worker 线程只处理自有 C++ 数据与文件 I/O | 13 个方法名、参数/Promise 语义及已有错误码保持；原占位响应必然改变，仅 `jpeg-pdf` 的受支持输入可成功；其他路线继续如实失败 |
| `entry/src/main/cpp/engines/image/image_converter.cpp` 与生产适配文件 | 把已验证的隔离原型适配到 `IConverter`，使用分块文件 I/O、受限 JPEG 解析、DCT 原字节嵌入、候选文件及独立校验 | image 工厂将不再总是 `MissingConverter`；其他四类引擎保持占位；不引入全文件 `vector` 缓冲或未审计的 PDF 写入器 |
| `entry/src/main/cpp/CMakeLists.txt` 和生成的源清单 | 为双 ABI 加入必要的生产适配与经过锁定的 JPEG 依赖；主机 mock、原型 CLI 不进入 HAP | 构建依赖和包内容发生变化，须验证实际 SDK/ABI 与第三方许可 |
| `shared/format-registry/conversion-matrix.json`、生成结果及状态测试 | **仅在生产链路、独立输出校验、保护阻断和设备验收全部通过后**，将 `jpeg-pdf` 从 `planned` 改为 `available`，由生成器重建 ArkTS 目录、rawfile、manifest 与 C++ 哈希；同步改写“全部 planned”的测试断言 | 这会改变已有格式目录和真实执行门禁，属于需审核的已开发行为调整；不修改 `docs/migration-source` 只读溯源文件，不提前宣称可用 |
| `README.md`、`docs/IMPLEMENTATION_STATUS.md`、验证记录 | 如实区分“Native 已接入但尚未发布”与“设备验收后可用”；保留历史验证记录 | 只以实测证据更新状态，不把主机原型或未签名包写成应用交付 |

## 对上传提示词的必要修正

1. `converter.h` 的 `CandidateOutput` 是文件候选元数据，`TaskContext` 尚无文件句柄，`InputProbe` 没有 `byteSize/sha256` 字段。生产实现应添加内部适配层并遵守现有 ArkTS DTO，不能按提示词虚构字段或将完整 PDF 放进内存向量。
2. `AuthorizedInputTask` 传入的是 **matrixSha256**。Native 会话必须与 `kMatrixHash` 核对，不应与 `kFormatsHash` 核对；配置变更必须运行 `tools/generate-registry.cjs`，不能手改生成文件。
3. ArkTS 约定 `initializeSession`、`registerWorkspace` 等返回 Promise。可在主线程完成轻量校验，但返回类型和时序契约不得改成裸字符串。工作区已由 ArkTS 创建，Native 应核验目录和归属，不自行创建或信任任意调用者路径。
4. 只读 512 字节和后缀无法证明 JPEG 完整、未加密或不受保护。仅对完整验证的受限 JPEG 返回 `actualFormatId=jpeg`、`protection=none`、`needsDeepCheck=false`；未知、无法检查或其他格式一律不能穿过 ArkTS 门禁。PDF 的 `/Encrypt` 文本搜索不是可靠的 PDF 安全解析。
5. 原型明确不支持 SOF2/渐进式、EXIF、ICC、CMYK，不能按提示词直接宣称通用 JPEG 或 `extreme` 保真。`text=1.0`、`layout=1.0` 之类无测量值不能伪造；保真报告应给出真实适用项、证据和未覆盖项。页面尺寸按受支持的 JFIF 密度规则，不简单用像素数当 PDF 点数。
6. `napi_env`、`napi_value` 与 JS 函数调用只在允许的完成回调线程进行；worker 不调用 `napi_call_function`。取消、暂停和释放要以任务所有权和安全点为准；单步快速转换可对暂停返回 `unsupported`，不假称已暂停。
7. 当前 route 配置、生成目录和多个测试均固定为 `planned`；提示词所列 `docs/migration-source/.../conversion-matrix.json` 是历史副本，不能作为运行时源修改。真正源在 `shared/format-registry`。

## 实施与验收门槛

1. 先做会话/工作区所有权、路径规范化与防符号链接逃逸、输入大小/摘要/完整 JPEG/保护状态校验；失败时没有输出或成功报告。
2. 将隔离原型接入受控生产适配，候选 PDF 写入临时文件；独立解析校验结构、页数和嵌入 JPEG 字节；仅在校验成功后原子提交 Artifact，提供幂等释放。
3. 覆盖异步失败、两任务并发、取消竞态、资源超限、坏图、伪造扩展名、未知保护状态、重复释放与关闭；保持演示、18/43 目录和其余 42 条规划路线的回归。
4. 运行 ArkTS 宿主检查、C++/NAPI CTest、独立 PDF 解析/渲染、应用与 ohosTest 构建及双 ABI 包核验。设备连接、合法调试签名、真实 Picker、PDF 打开/视觉检查和资源测试缺一时，仅报告待设备验收，不将路线标为 `available`。
5. 获得本次审核许可后才修改上述现有代码；通过最终门槛后同步源码、生成配置、测试和文档到原 GitHub 仓库。若实际实现需要超出本表的新行为调整，再单独提交审核。

## 本次需确认的边界

建议批准 **生产 C++ 接入及必要的构建/测试修改，但先保持 `jpeg-pdf` 为 `planned`**。待完整设备和发布证据齐备，再审核并执行配置激活。这样可以开发和验证真实链路，同时避免在无设备证据时向用户宣称路线可用。
