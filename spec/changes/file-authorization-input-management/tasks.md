# 实现任务清单：文件授权与输入管理

2026-09-29。采用用户批准的兼容方案，差异见 [implementation-review.md](implementation-review.md)。实现项与外部验收分别记录。

## T1：数据模型
- [x] SessionModels：PickedFile、AuthorizedFile、SessionContext、平台契约
- [x] 区分本地所有权与原 Native SessionInit/不透明 workspace 句柄；ArkTS 编译通过

## T2：格式检测
- [x] detectByExtension、detectByMime、detect；扩展名优先，MIME 回退及冲突警告
- [x] 覆盖实际已批准 18 格式和别名；不添加未注册 DOC/EPUB/视频
- [x] 6 个 Hypium 源码用例和全目录扩展名/MIME 检查通过

## T3：文件授权服务
- [x] EntryAbility 注入上下文；缺少上下文/能力时入口不可用
- [x] DocumentViewPicker.select，最多 10 文件，取消返回空数组
- [x] UUID 会话、inputs 目录、随机内部文件名
- [x] URI 描述符、256 KiB 分块及部分读写、实际大小/目标 stat、SHA-256
- [x] 单文件 100 MiB、会话 300 MiB、空文件/空间/授权错误校验
- [x] 移除、失败回滚、串行复制、幂等销毁及清理重试
- [ ] 真机 Picker、真实沙箱读写和摘要验收（未连接设备）

## T4：ConverterPage
- [x] authorizedFiles、sessionContext、filePickerAvailable 状态
- [x] 选择、复制状态、文件卡片及移除按钮
- [x] 首份文件选中源格式；保留原路线/意图/最低等级/质量筛选
- [x] 真实输入独立确认/提交；无输入时保留完整演示
- [x] 预览提示、复制中离页取消、输入所有权转交；ArkTS 编译通过
- [ ] Previewer 点击与读屏（未执行）

## T5：TaskStore
- [x] 新增 submitTask 接受 AuthorizedFile[] 和 SessionContext；原 enqueue 不变
- [x] 使用实际 initializeSession/registerWorkspace，不新增不存在的 sessionInit/convert
- [x] 原 ConvertRequest/PreparedInput、prepare/enqueueNative 和原执行门禁
- [x] 真实提交保持单文件；最多 10 文件仅用于选择与管理
- [x] 初始化五秒超时、迟到注册释放
- [x] C++ 占位如实形成 failed 真实记录，不回退 demo
- [x] 排队取消释放注册；运行取消等待 Native 释放再清理输入
- [x] 原 22 个 TaskStore 方法及 7 个规划/Native/目录文件基线一致

## T6：权限与资源
- [x] 按批准方案使用 Picker 授权；module.json5 不增加 FILE_ACCESS_MANAGER
- [x] 新增中英文选择/提示/失败/确认资源，已有文案保持
- [x] 应用和测试包资源编译通过

## T7：EntryAbility
- [x] onCreate 配置服务；onDestroy 关闭任务并清理受控会话
- [x] 等待活动 Native 调用；旧 Ability 清理绑定旧管理器
- [x] 宿主检查验证正常生命周期；强制终止恢复扫描不在本次范围
- [ ] 真机正常退出目录清理（未连接设备）

## T8：构建与验证
- [x] 152 项宿主检查通过（35 项输入管理、61 项 Hypium 源码）
- [x] 应用与 ohosTest Hvigor 编译通过，ArkTS 零编译错误
- [x] HAP 双 ABI、字节码及完整 rawfile 检查通过
- [ ] 独立编辑器诊断（工具不可用）
- [ ] Previewer 打开/点击 ConverterPage（未执行）
- [ ] 设备 Hypium、真实 Picker、退出清理（hdc 返回空）
- [ ] 真实转换端到端（C++ 占位保留，另项开发）
