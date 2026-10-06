# HarmonyOS OCR / PDFKit 可行性原型

独立 Stage 测试应用，没有注册主引擎、开放路线或实现六方向 Office 转换。固定依赖和摘要在 dependencies.json，使用 HarmonyOS BiSheng，不接受 Android/桌面库。

工程根目录 PowerShell：

```powershell
./prototypes/ocr-harmony/build.ps1 -SdkRoot 'D:/DevEco Studio2026/DevEco Studio/sdk/default' -Abi arm64-v8a
./prototypes/ocr-harmony/build.ps1 -SdkRoot 'D:/DevEco Studio2026/DevEco Studio/sdk/default' -Abi x86_64
./prototypes/ocr-harmony/create-test-app.ps1 -SdkRoot 'D:/DevEco Studio2026/DevEco Studio/sdk/default'
```

需要 CMake≥3.24、Ninja、tar、Node.js、PowerShell。本次 CMake4.4.3、SDK Clang15.0.4。脚本下载并核对固定源码和模型，输出在 tmp/offline-engines；TIFF try_run 结果明确设为关闭，因为没有构建 TIFF；CMP0137 向上游 IPO 测试传递 SDK 参数，没有修改第三方源码。

打开 tmp/offline-engines/stage-probe-app，用 DevEco 安装 ohpm 依赖并 debug assembleHap。可用 bundled Node 执行 tools/ohpm/bin/pm-cli.js install --all，再运行 Hvigor；DEVECO_SDK_HOME 指向 sdk，JAVA_HOME 指向 jbr。x86_64 仅编译。**临时工程复制本地签名配置并使用同一 bundle，安装会暂时替换转换应用，测试结束必须重装主工程签名 HAP。tmp 和签名材料禁止提交。**

模型、Apache/BSD许可原文和依赖清单随测试包提供，没有 INTERNET 权限。固定两行中英文 PGM 和两页 PDF 由脚本生成，不读取用户文档；用本机字体绘制栅格，没有嵌入/再分发字体文件。第一个按钮识别 PGM，第二个按钮检查官方 PDFKit 对象/渲染及扫描 OCR 数据连接。

NAPI 使用 Promise＋create/queue_async_work；worker 仅操作自有 C++ 数据，completion 创建 JS 返回值；句柄单次释放，异常不跨 C ABI。没有实现进度、取消、保护检测、受控产物或可靠 Native 内存硬限。

Leptonica codecs、Tesseract legacy/training/OpenMP/curl/archive/nativeCPU 优化关闭。PGM、PDF桥接只覆盖1400×260灰度样例及RGBA/BGRA布局，不是通用图像适配器。平均置信度不是文档准确率；ru_maxrss 是包含ArkUI/VM的测试进程峰值，不能代表192MiB Native分配或硬限。

实测与限制见 [开发记录](../../docs/DEVICE-ENTRY-AND-OFFLINE-ENGINES.md) 和 [脱敏结果](../../tests/generated/ocr-harmony-feasibility.json)。
