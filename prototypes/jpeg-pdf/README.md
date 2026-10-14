# 隔离的 JPEG→PDF 原型

此目录由用户于 2026-09-30 批准作为独立主机原型，其核心现已复用于主应用的实验性 JPEG→PDF Debug 路线。CLI 仍是主机验证入口，不能替代设备验收；Release 与其他 42 条路线保持关闭。2026-10-07 的 EXIF/ICC 兼容修复及真实设备证据见[本轮记录](../../docs/JPEG-METADATA-COMPATIBILITY.md)。

## 输入子集与输出

- 仅接收单张 **8 位 Baseline SOF0 JPEG**，灰度或 3 分量 RGB/YCbCr，最多 100 MiB、1600 万像素；扫描结束和 EOI 后不允许截断、警告或额外字节。首个 SOF0 须在 64 KiB 的首个流块中，超过此界限的合法 JPEG 也明确失败。
- 支持 EXIF APP1 的八种方向及可解释的物理分辨率、ICC APP2 的受限 RGB/灰度 v2/v4 配置。拒绝渐进式、算术/无损、CMYK、XMP、未知 APP 标记及无匹配 ICC 的非 sRGB EXIF 色彩标记。无 EXIF 物理分辨率时沿用 JFIF 密度，均缺失时使用 72 dpi；超过 PDF 页面范围则失败。
- 输出单页单图 PDF；无 ICC 时为 1.4，带 ICC 时为 1.7，使用 ICCBased 色彩空间并按 EXIF 设置图像矩阵。原 JPEG 压缩字节与 ICC 配置均保留，不重编码。图片 IR 有 Builder/Visitor/Writer 和样式级联解析；第一条路线只使用默认不透明白背景。完整文档结构、文本/表格 IR 与真正的全局保真策略尚未建立。
- IStream/ISink 支持部分读写、固定 64 KiB 块、取消/超时和输入/像素/临时空间限额。JPEG 解码库的分配请求按实例计数并限制，禁止 backing store；报告的 trackedAllocationPeak 包括这些请求和本层显式缓冲，不是进程 RSS 或系统分配器开销的准确值。最终真实执行还需独立的沙箱授权、输入摘要/保护探测、输出归属与设备资源隔离。
- 先写同目录独占的 JPEG 副本和候选 PDF，输出名使用只在不存在时成功的硬链接建立。任何失败清理本进程创建的临时文件。原型不接收 ArkTS 授权凭据，主机 CLI 路径由调用者明确提供；Windows CLI 使用本机窄字符路径，仅作为测试入口。

## 依赖、构建与测试

主机版本使用 [libjpeg-turbo 官方 3.1.4.1 发布包](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/tag/3.1.4.1)，SHA-256 固定为 `ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022`。构建时自动校验下载；也可将 `HDM_JPEG_ARCHIVE` 指向已有的官方压缩包离线重现。上游要求独立顶层构建，CMake 以 ExternalProject 实现；第三方源码和主机测试产物均不进入应用 HAP。依赖许可见[上游 LICENSE.md](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/3.1.4.1/LICENSE.md)。PDF DCTDecode/XObject 用法参照 [Adobe PDF Reference 1.6](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.6.pdf)。

```powershell
cmake -S prototypes/jpeg-pdf -B tests/native/jpeg-pdf-clean-build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build tests/native/jpeg-pdf-clean-build --target hdm_jpeg_pdf_cli hdm_jpeg_pdf_tests
ctest --test-dir tests/native/jpeg-pdf-clean-build --output-on-failure
python prototypes/jpeg-pdf/tests/integration.py tests/native/jpeg-pdf-clean-build/hdm_jpeg_pdf_cli.exe /path/to/pdftoppm
```

集成测试依赖 Pillow、pypdf 与 Poppler，生成样本至 `output/pdf/`、中间渲染至 `tmp/pdfs/`。它用**独立 PDF 解析器**核对页尺寸、图片对象、DCT 数据与原 JPEG 的逐字节相等，再以 Poppler 渲染到 PNG 并比较像素。两种解码/渲染实现有小差异，因此像素均值阈值 6 是原型回归门槛，不是极致保真等级认证。原应用 `validationProfileId=image_pdf` 仍是配置字段；本原型的 payload 身份检查不构成可发布的 releaseEvidenceId。

早期主机测试及实测数据见 [历史验证记录](../../docs/VALIDATION-NATIVE-READINESS.md)。Debug 接入已有设备样例证据，Release 发布仍需独立验收。
