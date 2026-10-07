# 原工程 JPEG 真机调试修复

日期：2026-10-07。用户授权自动修复其正在使用的 `D:\HarmonyOS\harmonyOS`，无需手动同步文件或修改开关。

## 已修复

- 将已验证的 JPEG Debug 门禁、配置生成器、双语入口文案及 Native 结果序列化同步到原工程。源配置、rawfile、ArkTS 目录和 Native 元数据一致，JPEG 为 experimental，仅 Debug 可执行；其余 42 条路线保持 planned。
- 保留本地个人签名配置，以及 `FormatDetector.ets` 中已有的本地改动。替换前文件保存在本地 `tmp/jpeg-debug-sync-backup-20261007-185708`；签名材料未复制或提交。
- 新增真实设备测试后，复现 `IO_ERROR / NATIVE_OUTPUT_COMMIT`：产物已经生成且校验通过，但沙箱拒绝硬链接提交。OHOS 分支改用 SDK 的 `renameat2(..., RENAME_NOREPLACE)`，原子提交且禁止覆盖已有文件；校验、授权、资源预算、取消和失败清理保留。
- 已从原工程重新构建 Debug 主应用和测试包，安装到连接的手机，并重新启动主应用。后续可继续使用原工程的 default 产品、Debug 模式。

## 本轮验证

- 12 组相关 ArkTS/配置/既有契约宿主检查通过，其中 JPEG 门禁回归 4 项；Native CTest 24/24 通过。完整旧逐字节保护脚本仍属于历史基线，不宣称本轮通过。
- 主应用和 ohosTest 的实际 Hvigor 构建通过，主应用含 arm64-v8a / x86_64，`BuildProfile.DEBUG=true`，打包 rawfile 摘要与源一致。
- 真机 Hypium **64/64** 通过。新增 `JpegDebugSmoke` 用仓库内 634 字节、8×8 的合成 baseline JPEG，经实际 NativeBridge 完成会话、能力/配置校验、工作区、深层探测、转换、PDF 校验、产物复制及释放。未使用替代引擎或模拟结果。
- 从设备日志取回该合成样例的 PDF 字节，独立 pypdf 解析和 Poppler 渲染通过：1 页、8×8 pt、嵌入 JPEG 字节完全一致；72 DPI 渲染尺寸相同，平均像素差为 0。PDF 为 1351 字节，SHA-256 `0114650536ba75a354953318781f95a1d32a7bf6d20c4730f41765e5d664dd3c`。这是一张微型合成测试图，不是复杂用户照片的验收。

完整结果见 [本轮验证报告](../tests/generated/jpeg-local-sync-validation.json) 和 [独立 PDF 验证报告](../tests/generated/jpeg-local-sync-pdf-validation.json)。手机测试的最初两次失败来自新用例未遵循 cache 根目录约定、未初始化资源注册表，修正测试设置后才复现上述真实产物提交错误；没有因此放宽生产门禁。

## 使用与未完成项目

继续打开原工程，选择 JPEG→PDF，切换到真实文件输入再导入。当前只支持受限 baseline SOF0、8 位灰度/RGB、受支持 JFIF 的单图；PNG、渐进式 JPEG、EXIF/ICC、CMYK 等不能据此宣称支持。扩展名为 JPG 也不保证符合子集。

本轮自动测试没有操作系统 Picker、文档保存界面、独立阅读器或 ShareKit；没有处理用户文档，也没有验证首次断网、持续运行或 Release 发布资格。Word/PPT→PDF 的 LibreOffice 构建结果仍在独立移植缓存，尚未打包或接入本应用；其他格式仍须实现各自的后端。没有把规划目录改成通用可用能力。

复现设备测试：从原工程构建并安装 Debug 主应用与 ohosTest 包，执行：

```text
hdc shell aa test -b com.example.os_softwaredevelopment -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000
hdc shell hilog -x -T JpegDebugSmoke
```

用 `tests/check-jpeg-device-pdf.py` 检查保存到 `tmp/jpeg-sync-smoke-hilog.log` 的本测试专用日志；需要 Python 的 pypdf/Pillow 及本机 bundled Poppler。测试用例只记录仓库合成样例的 PDF 字节，不记录用户文件或正文。主应用不包含这个测试用例或测试图片。
