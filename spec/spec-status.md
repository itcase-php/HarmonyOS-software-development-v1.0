# SDD 状态追踪

更新日期：2026-10-01

## 当前变更

| 变更名 | 状态 | 创建日期 | 描述 |
|--------|------|----------|------|
| file-authorization-input-management | implemented_pending_device_validation | 2026-09-29 | 已完成批准范围内 ArkTS 输入管理与真实提交入口；152 项宿主检查、应用/测试编译通过，设备/预览验收待执行，Native 会话/引擎仍占位 |

| deep-architecture-refactor | implemented_pending_device_validation | 2026-09-30 | 批准兼容方案已实现，173 项宿主检查及应用/测试编译通过；保持 18/43 和原演示，设备/预览验收待执行 |
| native-readiness-and-copy-safety | compatible_and_isolated_prototype_verified_native_integration_pending_review | 2026-09-30 | 兼容优化及 205 项 ArkTS/13 项 C++ 检查、隔离 JPEG→PDF 原型 4 项 C++/15 项独立 PDF 检查完成；应用/测试编译通过；生产 Native 接入另审 |
| jpeg-pdf-production | implemented_pending_device_validation | 2026-10-01 | 用户批准分阶段接入且暂不激活；受限转换核心进入双 ABI Native 构建，主机运行时、独立 PDF 解析/渲染、应用和 ohosTest 编译通过；路线保持 planned，能力为 0，设备和发布证据待审核 |

## 状态说明

- `created`：变更目录已创建，需求探索待开始
- `exploring`：需求探索进行中
- `proposal_done`：提案已批准
- `designing` / `design_done`：设计进行中 / 已批准
- `tasking` / `planning_done`：任务起草中 / 所有规划已批准
- `implementing`：实现进行中
- `verifying`：验证进行中
- `implemented_pending_device_validation`：代码及宿主/编译验证完成，设备或预览验收尚未执行；不是完整端到端交付
- `compatible_and_isolated_prototype_verified_native_integration_pending_review`：兼容优化与获批的独立原型已验证；应用真实引擎接入仍等待另外审核，设备/预览未验收
- `archived`：已归档
