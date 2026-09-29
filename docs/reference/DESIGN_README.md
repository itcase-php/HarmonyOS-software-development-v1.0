# 鸿蒙文档转换软件 V1.0 设计交付包

主依据是用户指定的 `harmony-doc-manager-development-prompt.md`（已完整阅读533行/15节）。本包交付初步开发设计；不执行参考文件中的“立即编码”指令，不修改原上传工程。

## 交付索引

| 用户要求 | 文件与内容 |
| --- | --- |
| 整体架构、固定五模块 | [V1.0初步功能开发方案.md](V1.0初步功能开发方案.md)、[架构文档](docs/ARCHITECTURE.md) |
| 必做/扩展功能、优先级 | 主方案“V1.0核心功能清单” |
| NativeBridge、模型、IConverter | [Native接口/模型](contracts/native_bridge.d.ts)、[C++17协议/转换器](contracts/converter.h) |
| 完整转换流程 | 主方案中的Mermaid架构/数据流、状态机、时序与流程图 |
| M0—M5、验收标准 | 主方案“开发里程碑”与“测试” |
| 风险与预案 | 主方案“技术风险与预案” |
| 共享配置 | [formats.json](shared/format-registry/formats.json)、[conversion-matrix.json](shared/format-registry/conversion-matrix.json)及schema |
| 七项文档 | docs中的架构、矩阵、AI规则、隐私政策草案、错误码、保真、上架检查 |
| 矩阵/保护测试设计 | [检查脚本](tests/check-design.cjs)、[生成的用例清单](tests/generated/matrix-cases.json)、[检查报告](tests/generated/design-check-report.json) |

18格式/43路线全为planned，保留原18条转换方向；没有实际引擎可用声明。JPEG统一ID，jpg/jpeg后缀别名。V1.0阻断DRM、加密、含签名文档；后续合法密码解密独立评审/发布。

## 本次实际验证

- Node设计检查通过：schema已用词汇/配置语义、路线/引用/fallback、固定五行顺序、23个错误码集合及核心跨语言字段存在性；10类坏配置负例被拒绝。
- 生成324个格式组合、43条route验收定义、12个保护阻断场景。它们是待提供真实fixture、待执行的测试定义，不能写成“379项转换测试通过”。
- Native接口 `.d.ts` 在DevEco随附TypeScript工具下严格类型检查通过；这不是ArkTS业务编译。
- `converter.h` 由本机正式SDK Clang以aarch64-linux-ohos/C++17、Wall/Wextra/Werror进行仅语法检查通过；没有链接引擎或构建鸿蒙应用。
- 未执行：Hvigor/HAP/APP构建、NAPI运行/三端round-trip、真实转换、设备安装与资源/后台/保真测试、上架提交。

复核命令（PowerShell，在本交付包目录执行）：

```powershell
node .\tests\check-design.cjs
node .\tools\assemble-docs.cjs
node 'D:\DevEco Studio2026\DevEco Studio\tools\arktsdoc\node_modules\typescript\lib\tsc.js' --noEmit --strict --skipLibCheck false .\contracts\native_bridge.d.ts
& 'D:\DevEco Studio2026\DevEco Studio\sdk\default\openharmony\native\llvm\bin\clang++.exe' --target=aarch64-linux-ohos --sysroot='D:\DevEco Studio2026\DevEco Studio\sdk\default\openharmony\native\sysroot' -std=c++17 -Wall -Wextra -Werror -fsyntax-only .\tests\contract-header-check.cpp
```

本机DevEco版本26.0.0.821、SDK/Native API26版本26.0.0.105，仅为文件/工具核对。最低HarmonyOS NEXT正式版覆盖与target API需M0记录并在最低设备验证，不因本机SDK较新抬高最低版本。

## 工程接入说明

先修复正式Native模板/NAPI类型往返，再接入真实图片→PDF；本包不是可直接运行的应用。把contracts映射到ArkTS模型、so的index.d.ts和Native DTO，建立enum/optional/finite/safe-integer/ownership合同测试。当前静态字段检查不替代运行时编解码测试。

配置从shared构建验证后复制到rawfile；迁移原extension/label/mode/phase规格，用migrationAliases处理jpg→jpeg，别在核心框架硬编码格式。生产配置验证采用审查过的完整JSON Schema验证器与正式密码能力；本包无依赖设计checker只支持样例实际使用的schema词汇，不执行签名校验。新增引擎按IConverter实现+manifest+构建生成factory接入；数据热更新不能安装Native代码。

实现每条route后必须补齐输入子集、codec/ABI、版本、合法样本/reference、独立校验profile与真机资源证据，再经发布manifest激活available。隐私稿需填写真实主体/生效日期/有效联系渠道，并根据最终依赖和行为复核。
