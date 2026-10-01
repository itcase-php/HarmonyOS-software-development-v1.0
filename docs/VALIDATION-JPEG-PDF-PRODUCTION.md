# JPEG→PDF 生产接入：分阶段验证记录

日期：2026-10-01。用户已批准[生产接入审核方案](../spec/changes/jpeg-pdf-production/approval-request.md)，明确“分阶段接入，暂不激活路线”。本记录只覆盖当前主机和编译证据。

## 本阶段实际完成

- 将已验证的受限 JPEG 解析、图片 IR 与 PDF Writer 源码编入应用 Native 双 ABI 构建；引入 SHA-256、会话/工作区运行时、`IConverter` 的 image 适配、固定结构 PDF 校验与 NAPI 异步绑定。依赖为 SHA-256 锁定的 libjpeg-turbo 3.1.4.1；其 `LICENSE.md` 与 `README.ijg` 打包在 HAP 的 `resources/rawfile/licenses/libjpeg-turbo/`。
- 会话要求 schema、configVersion 和 matrix SHA-256 一致；受控目录、随机文件 ID、文件大小、SHA-256、完整受限 JPEG 解析全部通过才给出确定探测。候选 PDF 经内部结构与 JPEG payload 身份校验后提交；失败清理临时文件，取消与产物释放有主机测试。
- Native 计划校验绑定 `jpeg-pdf`、安全策略版本、单步 image+pdf、输入/输出格式和空降级/回退；未知选项被拒绝。单图输入仅限 8 位 Baseline SOF0 灰度或三分量 JPEG；渐进式、EXIF/XMP/ICC、CMYK 等不在支持范围。
- `shared/format-registry/conversion-matrix.json` 中 `jpeg-pdf` 继续为 `planned`，18 种格式和 43 条规划路线不变。`getCapabilities` 继续返回空 engines/routes，NAPI `execute` 在 planned 状态返回 `failed / ENGINE_MISSING`。内部 C++ 运行时可执行测试，但应用不能获得可用路线。未生成 releaseEvidenceId，也未声称 `extreme` 保真。
- ArkTS 手写源码、`NativeProtocol`、迁移溯源文件和其他四类引擎未修改。

## 已执行验证

| 检查 | 实际结果 |
| --- | --- |
| ArkTS 宿主脚本 | `check-interactions`、`check-copy-safety`、`check-fidelity`、`check-refactor`、`check-hypium-host`、`check-audit`、`check-input-management`、`check-architecture`、`check-design`、`check-migration` 全部通过；生成器复核 18/43 且原哈希不变 |
| MSVC 主机 CTest | 21/21 通过，包括 SHA-256、PDF 结构校验、生产运行时、原核心/mock NAPI 与独立原型用例。原 mock NAPI 仍编译历史占位分支，因此不作为新 NAPI 分支的运行时证据 |
| 生产运行时外部 PDF 检查 | 8×8 Baseline JPEG 经内部运行时生成单页 PDF；pypdf strict 解析为 1 页 1 图，嵌入 JPEG 与输入逐字节相同；Poppler 72 dpi 渲染为 8×8，平均像素差 0。另验证伪造计划、旧策略、摘要不符、坏 JPEG、取消及重复释放 |
| 独立原型集成 | 15/15 通过，包括 RGB/灰度的 pypdf 解析、Poppler 渲染和坏图/超限/取消。大尺寸样本像素差阈值属于原型回归门槛，不是保真等级认证 |
| HarmonyOS 编译 | `entry@default` 与 `entry@ohosTest` 的 `assembleHap` 成功；HAP 内有 arm64-v8a 和 x86_64 的 `libentry.so`、矩阵 rawfile 及第三方许可文本。应用包未签名；SDK 能力、模板资源与工具链警告仍存在 |
| 设备 | `hdc list targets` 为 `[Empty]`，未运行安装、真实 Picker、设备 NAPI、PDF 打开、Hypium 或读屏验收 |

应用编译日志：`tests/generated/jpeg-pdf-production-build.log`；ohosTest 编译日志：`tests/generated/jpeg-pdf-production-ohosTest-build.log`。测试输出位于忽略提交的 `tests/native/`；主机生成 PDF 与渲染 PNG 位于忽略提交的 `output/pdf/` 和 `tmp/pdfs/`。

## 激活前仍需完成

1. 在合法签名的真机或模拟器上验证 Picker 授权、缓存目录与权限、NAPI Promise、受限 JPEG 探测、真实文件转换、PDF 打开及可视结果；补充生产 NAPI 分支的设备或等价宿主测试。
2. 针对文件替换、符号链接与检查到打开之间的路径竞态做平台级文件描述符加固；验证双任务并发、取消/释放竞态、资源上限和临时文件清理。当前路径与摘要校验是第一层防护，不构成最终竞态证明。
3. 实现用户可访问的产物导出和真实保真报告/测量；核对设备内存、时间、存储占用，完成第三方许可及离线发布检查。
4. 将设备与发布证据提交用户单独审核；获批后才修改共享矩阵路线状态、生成能力与相应断言。当前真实可用路线保持 0。
