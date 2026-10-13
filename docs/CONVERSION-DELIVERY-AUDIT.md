# 四条路线：转换内容与 PDF 交付复查

日期：2026-10-13。范围：JPEG、PNG、DOCX、PPTX → PDF；没有连接设备。四条路线继续允许 Debug / Release 执行，其余路线保持禁用。

## 保存与分享

发现的缺口是：复制返回正确大小只能证明写入调用完成，不能证明目标提供者最终保留了正确内容；退出作用域时也可能释放仍在保存或分享的 Native 产物。

- 系统保存使用选择器授权的 URI，以 READ_WRITE / CREATE / TRUNC 打开。写入后先关闭描述符，再通过 URI 重新读取并分块计算 SHA-256；大小和摘要均匹配才记为保存成功。保存 URI 的读写授权与打开方式依据 [OpenHarmony 保存用户文件说明](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/save-user-file.md)。
- 分享副本也执行相同核验，错误副本不打开分享面板。分享路径只由已经校验的不透明产物引用生成，避免把其他 ID 当路径。文件名去除控制字符，并按 Unicode 字符截断。
- 保存或分享进行中，作用域退出延迟释放该产物；旧作用域迟到清理不能关闭新作用域使用的全局 Native Runtime。正常结束后再完成对应清理。
- 失败保留原始受控 PDF 以便重试。分享面板出现仅代表系统接管分享流程，不能证明接收应用已经收到文件。强制结束进程以及各文件提供者的真实行为仍待设备检查。

## 图片、文字和字体

- JPEG 回归重新执行 29 项实际转换、独立 PDF 解析与 Poppler 渲染；验证嵌入 JPEG / ICC 字节、EXIF 方向及尺寸。PNG 六种模式实际转换，逐像素核对 RGB / 透明度并检查物理尺寸；渲染目视检查通过。
- Office 导入前检查内嵌 PNG / JPEG 的实际解码，包含透明 PNG 与渐进 JPEG。ZIP CRC 正确但图片数据损坏仍拒绝；其他内嵌编码尚未验收，明确拒绝，不把图片占位当成功。
- Office 增加正文字符数量下限和 PPTX 幻灯片页数摘要。输出由系统 PDFKit 提取并归一化文字，与源摘要比较；输出图片对象检查解码尺寸并释放 PixelMap。文字不足、页数不符或源文件含图片而输出完全没有图片时，拒绝完成与交付。
- Fontconfig 检查可用字体字符集是否覆盖源正文；缺字明确失败。缺失符号字体或私有区图标字符所需字体时，即使批准普通字体替代也拒绝，防止图标被错误替换。普通缺失字体继续默认拒绝，仅明确批准才允许替代。
- 原先 libentry.so 导出静态 JPEG 编解码及自定义内存函数，存在干扰 LibreOffice 自带编解码器的符号绑定风险。新增链接隔离；最终 HAP 的 libentry.so 不再导出这些静态编解码符号。没有把该风险描述为已经复现的设备故障。

正文摘要是私有的可选结果扩展，不包含原文字符串；验证后清除，不写入任务历史或报告。14 个 Native 方法和原有协议字段保留。

## 已验证与局限

| 检查 | 结果与范围 |
| --- | --- |
| Native CTest | 25/25，实际宿主 Native / mock NAPI 契约、JPEG 产物归属和复制 |
| JPEG 独立检查 | 29 项，实际编解码核心、pypdf 解析与 Poppler 渲染 |
| 核心文档检查 | 34 项，实际 PNG 转换、Office 包/文字摘要/内嵌图片解码；不包含 LibreOffice 导出 |
| 保存分享回归 | 13 项，实际 ArtifactDelivery，模拟 Picker / ShareKit / 提供者；含同大小错误内容、关闭后提交、短读和失败重试 |
| 交付生命周期 | 3 项，实际 TaskStore / ServiceContainer，模拟 Native；含退出时仍在保存/分享、新作用域隔离 |
| Office 资源 / PDF 检查 | 22 项，实际 ArkTS 配合 Node IO、模拟解压 / PDFKit；含文字、图片、页数与 PixelMap 清理失败 |
| Release SDK / HAP | 编译、签名、235 个 Office 库、3271 个资源及静态编解码符号隔离通过 |

对应报告在 `tests/generated/`：`jpeg-delivery-audit-host-report.json`、`core-document-engines.json`、`artifact-delivery-host-report.json`、`delivery-lifecycle-regression.json`、`bundled-runtime-regression.json`、`core-routes-release-hap-validation.json`。签名候选包与摘要见 [Release 候选记录](RELEASE-CANDIDATE.md)。旧设备证据保留，未将它改写成本轮验收。

字符下限比较不证明文字顺序、位置、颜色或全部内容都完全一致：重复文字可能掩盖部分缺失，页眉页脚不纳入 Word 主文档摘要。图片下限仅检查完全丢图和可解析性，不证明每张图都保留、矢量形状无损或摆放正确。字体库存和字符集覆盖也不等于最终字形与原排版一致。

隐藏幻灯片、修订、替代内容、复杂公式或文字转曲可能引发保守拒绝；当前检查没有为这些情况静默放宽通过条件。真正的 Office 初始化 / 导出、PDFKit SDK 行为、逐页参考 PDF 外观对比，以及新包的系统保存后独立打开 / 分享接收均待设备验收。本轮结果不能作为“任意文件绝不丢字、绝不损图、字体完全一致”的保证。

## GitHub 同步范围

同步生产源码、固定依赖源码归档、生成清单、复现脚本及上述回归证据。Office 大体积库和离线资源 ZIP 继续留在本机，仓库通过固定清单及移植 / 打包脚本复现；签名配置、证书和签名 HAP 不发布。其他电脑需先准备匹配的 Office Runtime，缺失时构建会明确失败。
