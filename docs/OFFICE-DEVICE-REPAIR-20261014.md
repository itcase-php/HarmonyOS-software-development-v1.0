# 2026-10-14 Office 故障修复与验证边界

本轮先在已授权的鸿蒙 arm64 设备上复现故障；用户随后移除设备，要求继续修改代码。移除后只做代码、交叉编译、主机回归及签名包检查，没有再次安装或启动设备测试。

## 已定位并修改

1. **离线清单摘要不一致。** Windows 文本写入把 LF 改为 CRLF，但生成常量对改写前的文本计算摘要，实际设备返回 `OFFICE_MANIFEST_MISMATCH`。改为直接写入确定的 UTF-8 字节，再对相同字节计算摘要。新增实际打包脚本回归，CMake 也核对两份清单及 C++ / ArkTS 生成常量，阻止不一致的包继续构建。此前 2026-10-13 Release 包也存在此问题，其成功打包记录不能证明 Office 能运行。
2. **Office 用户配置模板缺失。** 补入 `presets`，其中包括初始化必需的 `presets/basic/script.xlc`；打包与 Native 初始化分别检查该资源。修复前 LOK 因用户配置无法建立而退出，修复后设备能够进入文档导入。
3. **libetonyek 编译器运行时缺失。** 用官方 SDK 的 compiler-rt builtins 链接该库，消除 `__addtf3`、`__extenddftf2`、`__floatunsitf`、`__multf3` 强未解析导入。补丁为 `0012-ohos-libetonyek-builtins.patch`，未自行模拟浮点运算。
4. **UNO 公共类型信息未统一。** 设备确认存活的 `OStorage` 对象向下转换返回空值，且公共接口 RTTI 地址不一致，随后报 `no own storage`。现在先全局加载 `libuno_cppuhelpergcc3.so.3`，再加载 Office。设备上的 DOCX 测试越过该异常，进入 Writer 文档属性处理；这仍不是完整转换通过。
5. **UNO 桥接调用空的缓存刷新函数。** 最新 DOCX 崩溃的 PC 为 0，调用栈落在 `VtableFactory::flushCode`。原 Linux 分支通过 `dlsym(RTLD_DEFAULT, "__clear_cache")` 得到空指针后直接调用。OHOS 现在使用编译器内建调用，实际 SDK 重编译的桥接库含本地定义的 `__clear_cache`。`0014-ohos-uno-cache-flush.patch` 固定该改动；最终 HAP 的加载代码和数据与该库一致。**设备移除后才完成本修复，尚未在设备执行。**
6. **导入异常导致进程中止。** `0013-ohos-import-uno-errors.patch` 让 OHOS 下未被既有分支处理的 UNO 异常成为导入失败，而非落入 `abort`。保留原来的格式、安全和保护检查，没有把失败当作成功。

临时 stderr 重定向、对象地址打印和原始诊断日志读取均已从最终代码与库中移除。三个新增上游补丁均通过已应用状态的反向检查，配置脚本会自动应用它们。

## PDF 入口与 document_cli.cpp

PDF 继续仅作为输出格式。格式详情现在提供“将文件转为 PDF”，跳转到已有转换页；设备 UI 已确认该入口可以打开页面。没有开放 PDF→Word/PPT，也没有恢复禁用路线。其他格式按钮改为“使用此格式转换”。

`document_cli.cpp` 以前收到 `docx INPUT OUTPUT.pdf` 时只检查 OOXML，却返回 0；新增用例在修复前真实复现了这个问题。现在 Office 检查只接受 `docx|pptx INPUT`，明确输出 `inspection only`；带输出参数时返回用法错误 99。该主机工具不宣称执行 LibreOffice 导出。

图片 CLI 原来直接拼接 Native 内部产物文件名复制，绕过正式交付接口。现在先释放任务并删除输入工作区，再通过 `CopyArtifactToFd` 保存，关闭后回读 SHA-256，同时检查读取、打开和关闭失败。回归覆盖 PNG 实际像素/透明度与页面尺寸、JPEG 产物交付、不能把目录当作保存文件，以及 Office 检查不能冒充转换。

## 当前证据

| 项目 | 结果及限制 |
| --- | --- |
| Native CTest | 25/25 通过；主机测试，不运行鸿蒙 Office |
| 文档 CLI 与核心文档检查 | 38 项通过，PNG 独立 pypdf / Poppler 校验；JPEG 交付；Office 仅包检查 |
| 清单生成回归 | 实际打包脚本使用合成输入，验证 LF、摘要一致性及缺失 presets 拒绝 |
| 离线资源与 PDF 生命周期 | 22 项主机模型检查通过 |
| 保存 / 分享交付 | 13 项主机模型检查通过，不代表系统文件提供者与接收应用已验收 |
| 实际 SDK | Debug 主应用、ohosTest 及签名 Release 均构建成功 |
| 最终 HAP | 235 个 Office 库，3284 个离线文件；摘要、代码 / 数据、依赖、缓存刷新实现及 presets 检查通过；未声明 INTERNET 权限 |
| PNG 设备样例 | Native 转换、PDFKit 解析及任务清理后的文件描述符复制 / 回读摘要通过，1774 字节，SHA-256 `8dbccad5a84480efc67438e7a7443a5dc0a3c406ab782c257d06ea13092a37cc`；不是最终版本的设备复验 |
| DOCX 设备样例 | 原 `no own storage` 阻断后又发现上述缓存刷新崩溃；尚无成功导出的设备 PDF |
| PPTX 设备样例 | 之前复现 `no own storage`；加载顺序与缓存刷新修复后尚未在设备复验 |
| JPEG 设备情况 | 用户此前确认可转换；本轮最终包没有重新进行设备验收 |

最终签名 Release：`entry/build/default/outputs/default/entry-release-signed.hap`，392683857 字节，SHA-256 `0101543eaa666fd926b3e7358d6002f2b7594eab64771ea92c67c96c8ec98ecc`。清单摘要 `d24d315331984e9613e14a3bd85b450096a4f925df7951191942e9d4416255aa`。包留在本机，未提交二进制或签名资料。

可重跑证据见 `tests/generated/core-document-engines.json`、`core-routes-debug-hap-validation.json`、`core-routes-release-hap-validation.json` 和 `office-device-repair-20261014.json`。包内检查还会比较原始库与 Hvigor 去除非加载符号后的所有分配节，避免仅检查文件名而漏掉旧代码。

## 接回设备后的验收

在解锁的设备上安装最终主包与对应测试包，运行 `CorePdfSmoke`，分别检查 DOCX / PPTX / PNG 转换、系统 PDFKit 和任务清理后的产物交付。可选参数 `-s captureCorePdf true` 仅导出仓库自有样例的 PDF，便于电脑独立解析和渲染。

成功生成后，再核对页数、页面大小、正文和关键数值、表格、图片与逐页外观；另用中文及符号字体样例检查缺字和替代策略，并测试系统选择位置保存、重新打开及分享接收。当前没有证据可保证任意文件的文字、图标、字体和排版完全一致。四条路线仍为 `experimental`，没有填写设备验收通过或发布资格。
