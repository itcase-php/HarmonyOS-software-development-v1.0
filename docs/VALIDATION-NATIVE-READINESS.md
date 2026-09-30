# 原生就绪与副本安全验证

日期：2026-09-30；基线 e58878fb0d4d19429748b892cfa3716691fa2343。

已完成不改变已通过功能的兼容优化：异常消息、自有 DTO 副本、目录查询索引、历史淘汰、作用域实例调用、C++ 单元测试与工厂索引。用户批准了独立 JPEG→PDF 主机原型，真实 Native 链路接入另审。原型不改变应用中的 C++ 占位行为，也不构成应用已经实现真实转换的证据。

## 实际验证

205 项 ArkTS 宿主检查通过：交互 15、保真 13、原重构 12、Hypium 源码 61、审计 16、输入 35、架构 21、新副本/索引 32。新测试独立读取类型声明构造字段样本，覆盖所有新复制方法及可选字段存在/缺省/undefined 三种状态；修改返回对象不影响缓存。热查询不调用全量 listFormats，冷分类查询仅复制一次；初始化后索引跟随版本重建，校验失败保持旧目录。历史测试禁止 slice/reverse 并保护最旧活动项。

13 项 C++ CTest 编译运行通过，使用 GCC 8.1、C++17、-Wall/-Wextra/-Wpedantic/-Werror。5 项核心测试覆盖全部错误码、五个工厂、非法 ID、MissingConverter、RAII 和拥有消息的 what()；8 项桥接测试把实际 native_bridge.cpp 与明确的主机 NAPI 模型链接，覆盖 13 个接口、请求/schema、占位失败、控制/释放、异步排队/完成失败和异常兜底。模型强制区分 worker/completion 阶段，但不能证明实际系统线程和设备 NAPI 的行为。

独立 JPEG→PDF 原型另外通过 4 项 C++ CTest 和 15 项集成检查。它用固定 64 KiB 流块、受限 JPEG 解码内存与临时空间，生成单页 PDF 1.4；外部 pypdf 严格解析确认三份有效样本的 DCT 图片字节与源 JPEG 逐字节一致，Poppler 渲染并与独立解码结果比较。RGB 与灰度样本的平均像素绝对差分别为约 4.00 和 2.16，均低于原型回归阈值 6；大于单块的输入也通过。拒绝截断/尾随数据、渐进式、EXIF、ICC、CMYK，以及像素、解码分配、临时空间超限；验证取消和输出防覆盖。该像素门槛不代表应用的保真等级。依赖为固定 SHA-256 的 libjpeg-turbo 3.1.4.1 官方发布包，构建细节、受支持 JPEG 子集、风险和测试命令见[原型说明](../prototypes/jpeg-pdf/README.md)。产物在忽略的 output/pdf/，第三方构建目录不入 Git 或 HAP。

```powershell
node tests/check-copy-safety.cjs
cmake -S entry/src/main/cpp/tests -B tests/native/build -G Ninja -DCMAKE_CXX_COMPILER=g++ -DCMAKE_BUILD_TYPE=Debug
cmake --build tests/native/build
ctest --test-dir tests/native/build --output-on-failure
cmake -S prototypes/jpeg-pdf -B tests/native/jpeg-pdf-clean-build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build tests/native/jpeg-pdf-clean-build --target hdm_jpeg_pdf_cli hdm_jpeg_pdf_tests
ctest --test-dir tests/native/jpeg-pdf-clean-build --output-on-failure
python prototypes/jpeg-pdf/tests/integration.py tests/native/jpeg-pdf-clean-build/hdm_jpeg_pdf_cli.exe /path/to/pdftoppm
```

宿主 ArkTS 脚本沿用 HDM_TYPESCRIPT_PATH 设置。C++ 示例须在具备 CMake/Ninja/主机编译器的终端执行；本机实际编译器路径记录于验证 JSON。应用默认 HDM_BUILD_HOST_TESTS=OFF；不能将 mock NAPI 链接到设备库。Debug 实际命令含 -O0、C++17 和新增警告标志；Release 尚未构建，未强加优化级别。SDK 模块注册采用 C++17 初始化，字段与原值一致。

分步骤应用编译日志为 native-readiness-step1～step3-build.log，最终应用 native-readiness-final-app-build.log（15s594ms）。测试包日志 native-readiness-final-test-build.log。每步最终成功，曾发现并修复捕获变量收窄的 ArkTS 编译错误。builtin_check_editor_errors 当前不可调用，采用实际 Hvigor 编译，不把它声称为编辑器验收。

## 保留与边界

保留 18 格式、43 规划路线、单文件/意图/最低等级筛选、质量排序、2/3.5/6 秒演示、FIFO/暂停/恢复/取消、100 条历史、文件授权和页面路由。NativeProtocol、converter.h、五个占位引擎、完整 shared/rawfile 和质量/保真控制接口逐字节保持基线；C++ 边界 what()、注册表和构建配置是本轮明确修改的文件，不能继续声称全部 C++ 不变。逐项 SHA-256 见 native-readiness-preservation-report.json。旧基线和旧验证记录不改写。

副本只覆盖既有类型声明的字段，不保证保留未声明的扩展字段；新增协议字段时字段覆盖测试要求同步补齐。查询继续返回调用者可修改的独立数据，不公开内部可变数组。H-04 保留兼容静态入口/旧构造默认参数，新增生产调用显式使用作用域实例。

HAP 核验双 ABI libentry.so、modules.abc、打包目录摘要和主机测试/原型未入包。摘要/产物/警告汇总见 native-readiness-validation-report.json；原型的 4+15 项实测分别见 jpeg-pdf-prototype-ctest.log、jpeg-pdf-prototype-integration.json。产物未签名，未安装；设备 Hypium、Previewer、真实系统 Picker/生命周期/读屏尚未执行。SDK crypto 能力、工具链参数、测试模板颜色和未签名警告保留。

五个应用引擎仍 unavailable；initializeSession/registerWorkspace/probeInputs 仍明确失败，execute 返回 ENGINE_MISSING，无应用输出和真实保真指标。真实可用路线为 0。隔离原型仅接受受限 JPEG 子集；尚未实现生产会话/工作区/保护探测、输出归属与通用保真，不能将原型 PDF 声称为用户可用的应用功能。审阅文本中的 contentRef、完整 DocumentIR 结构、随机 Demo 指标与当前源码不符，已在 implementation-review.md 逐项纠正。上传内容在 M-02 的问题位置结束，用户确认没有后文或独立开发提示词。
