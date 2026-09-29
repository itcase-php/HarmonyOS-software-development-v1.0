# 工程迁移验证

本文件保留 2026-09-28 的迁移阶段验收记录。2026-09-29 的新增交互功能与最新应用构建结果见《交互功能与使用说明》、tests/generated/interaction-build.log 和最新 build-check-report.json。

验证日期：2026-09-28；工程：`D:/HarmonyOS/harmonyOS`。迁移前先构建原生模板成功，再构建迁移后的工程；本报告描述后者。

## 已执行并通过

| 验证 | 实际结果 | 证据/限制 |
| --- | --- | --- |
| 原样归档与文件保留 | 21/21 交付文件原样副本与原 outputs SHA-256 一致；46 个原工程文件均仍存在，仅 6 个活动文件修改 | tests/generated/migration-check-report.json；原工程备份路径见状态文档 |
| 协议保留 | 原 ArkTS 全部模型与 13 API 保留，生成 Protocol.d.ts 与活动模型逐字等价；C++ converter.h 原字节保留 | 同上；不是运行时往返序列化测试 |
| 配置与图 | 18 格式、43 路线，10 类坏配置被拒绝 | tests/generated/design-check-report.json，仅设计范围 |
| 配置生成/打包 | ArkTS 强类型缓存与 JSON 等价，rawfile 与 shared 逐字节一致；所有 route 保持 planned | migration-check-report 和 hap-package-report |
| Native 类型包 | DevEco 随附 tsc --noEmit --strict --skipLibCheck false Index.d.ts，exit 0 | 已修正 .d.ts 导入 .ets 的失败，改为生成独立声明 |
| C++17 契约 | SDK OHOS Clang aarch64-linux-ohos / -Wall -Wextra -Werror / -fsyntax-only，exit 0 | 只验证头文件语法；实际 Native 双 ABI 编译由 Hvigor 完成 |
| 应用构建 | Hvigor assembleHap，BUILD SUCCESSFUL，exit 0；32s475ms，33 tasks，19 executed/14 up-to-date | 实际 CompileArkTS 与 CMake/Ninja 已完成，不是 Node 模拟构建 |
| HAP 结构 | arm64-v8a 与 x86_64 的 libentry.so、modules.abc、两份 JSON 和 manifest 均存在且非空；打包 JSON 与源码哈希一致 | tools/inspect-hap.ps1 / tests/generated/hap-package-report.json |

工具链是本机 DevEco Studio 26.0.0.821，项目 targetSdkVersion / compatibleSdkVersion 26.0.0，Native 编译器 BiSheng。未因迁移更换产品身份、SDK、ABI 或签名方式。

构建警告：SDK/BiSheng 对 `--gcc-toolchain` 提示 unused-command-line-argument；构建成功，未修改 SDK 工具链绕过此警告。签名阶段提示未配置 signingConfigs，跳过签名。实际产物是 `entry/build/default/outputs/default/entry-default-unsigned.hap`，不是可宣称安装/发布已验证的签名包。

## 未执行项

设备安装/运行、NAPI 运行时加载及复杂对象往返、Hypium 设备测试、真实图片→PDF、DRM/加密/签名内容检测、保护清理断言、保真测量、资源峰值/后台/取消/故障恢复均未验收。

324 格式组合、43 路线及 12 保护场景是完整保留的用例定义，未提供真实 fixture 或执行引擎，因此仍标为 not_executed。首页“可执行路径 0”反映真实占位状态。

原 VALIDATION-DESIGN.md 及原归档报告描述上一阶段“设计包未构建”；当前设计脚本仍仅做设计校验，其 scope 明确为 design_only。应用构建结果以本文件和 build-check-report.json 为准，不混淆两种报告。

## 复现

在工程根目录执行：

```powershell
node tools/generate-registry.cjs
node tests/check-migration.cjs
node tools/assemble-docs.cjs

node 'D:\DevEco Studio2026\DevEco Studio\tools\arktsdoc\node_modules\typescript\lib\tsc.js' --noEmit --strict --skipLibCheck false entry/src/main/cpp/types/libentry/Index.d.ts

& 'D:\DevEco Studio2026\DevEco Studio\sdk\default\openharmony\native\llvm\bin\clang++.exe' --target=aarch64-linux-ohos --sysroot='D:\DevEco Studio2026\DevEco Studio\sdk\default\openharmony\native\sysroot' -std=c++17 -Wall -Wextra -Werror -fsyntax-only tests/contract-header-check.cpp

$env:DEVECO_SDK_HOME='D:\DevEco Studio2026\DevEco Studio\sdk'
$env:JAVA_HOME='D:\DevEco Studio2026\DevEco Studio\jbr'
& 'D:\DevEco Studio2026\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
if ($LASTEXITCODE -ne 0) { throw 'Hvigor build failed' }
& ./tools/inspect-hap.ps1
```

本机工具位置只是复现当前结果；其他开发机通过相应 DevEco 安装路径设置环境。生成器由工程内源码/配置工作，不依赖旧 outputs 的绝对路径。

`check-migration.cjs` 固定检查本次迁移基线。未来协议、矩阵或 engine 工厂正式演进时，应在审查中同时更新相应基线断言和实现证据，保留 migration-source 原样记录。生成的报告不要被当作不可变验收历史；正式发布应单独存档带版本的测试证据。
