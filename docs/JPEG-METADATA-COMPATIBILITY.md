# JPEG EXIF/ICC 兼容修复

日期：2026-10-07。用户截图显示上一阶段的原因提示已生效，但普通 JPEG 仍因附加数据段被拒绝。本轮修复转换兼容性，不再仅修改提示。

## 已实现

- EXIF APP1：解析有界 TIFF 目录，支持大小端、八种方向及物理分辨率；用 PDF 图像矩阵旋转/镜像，必要时交换页宽高。结构错误和重复/冲突方向被拒绝。非 sRGB 色彩标记没有匹配 ICC 时拒绝，避免错误颜色解释。
- ICC APP2：核对分段编号/数量、重复/缺失、配置头、色彩分量及标签范围，支持受限 RGB/灰度 v2/v4 配置。重组配置后以 ICCBased 色彩空间写入 PDF 1.7，并应用配置的渲染意图。未知类型继续拒绝。
- 原 JPEG 以 DCTDecode 逐字节嵌入；EXIF 和 ICC 原始数据未被剥离，ICC 另写为可供 PDF 阅读器使用的色彩空间流。无 ICC 的原有 PDF 1.4 输出保留。
- 元数据缓冲和 libjpeg 保存的标记纳入既有内存预算；首个 SOF0 仍须在前 64 KiB，ICC 缓冲上限 64 KiB。渐进式、CMYK、XMP、未知 APP 和晚于已检查图像头的元数据仍不支持。
- 原生 PDF 校验扩展到含 ICC 的固定七对象结构，核对引用、分量和流长度，保留摘要、授权、资源预算、禁止覆盖及 Debug 门禁。NativeProtocol 未变更。

实现依据：[CIPA EXIF 方向定义](https://www.cipa.jp/std/documents/e/DC-008-2012_E.pdf)、[ICC 图像嵌入说明](https://www.color.org/profile_embedding/)、[PDF Association 色彩说明](https://pdfa.org/wp-content/uploads/2011/08/tn0002_color_in_pdfa-1_2008-03-141.pdf)。这些标准依据不替代本应用的样例验证或发布验收。

## 验证与交付

- 先新增回归，原实现明确拒绝 `exif-orientation-1`；修复后专项 **30 项**通过。覆盖八种方向、大小端、ICC 重组、分段缺失/重复/乱序、无效标签范围、EXIF 分辨率/色彩标记，以及仍须拒绝的未知 APP/XMP/晚到元数据。
- 每个有效样例均由独立 pypdf 解析，核对 JPEG/ICC 字节、页面尺寸；由 Poppler 渲染，对照 Pillow EXIF 方向及 LCMS 色彩解释。像素均值阈值 6 沿用已有回归标准，不代表任意文件视觉完全一致的承诺。
- 用户提供的截图本身含 456 字节 ICC，在主机真实转换通过，JPEG 与 ICC 均保持字节一致；1224×2700 渲染通过，平均像素差约 2.253。它不是截图内先前导入的另一个文件，不能宣称后者已实测通过。用户图片和 PDF 只保留本地，未提交或打入应用包。
- 原生 CTest **25/25**，含真实 EXIF/ICC 样例的 Runtime 转换及 ICC 输出校验变异测试；既有独立集成 **15/15**，12 组相关宿主检查通过。
- 实际 Hvigor Debug 主应用/ohosTest 构建通过，重新安装到手机。真机 Hypium **65/65**：基线与同时含 EXIF 方向 6、ICC 的仓库合成样例均通过真实 NativeBridge 转换、校验、产物复制和释放。
- 取回设备的合成样例 PDF，独立解析/渲染通过：ICC 588 字节保持一致，方向 6、页面和渲染尺寸 16×24，平均像素差约 1.612。测试只记录仓库合成数据，主应用不含测试图片。

结果见 [专项解析/渲染报告](../tests/generated/jpeg-metadata-host-report.json) 与 [构建和设备验证报告](../tests/generated/jpeg-metadata-validation.json)。新增样例位于 ohosTest；主机运行 `tests/check-jpeg-metadata.py <CLI>`，设备沿用 `JPEG-DEBUG-LOCAL-SYNC.md` 的测试命令，专项脚本可用 `--device-log` 核对取回的合成 PDF。

系统 Picker、用户原失败图片、保存/分享界面、首次断网、持续负载和 Release 尚未完成本轮验收；Office 与其他路线未因此开放。此前阶段文档中的 EXIF/ICC 拒绝规则属于历史状态，以本记录及当前源码为准。
