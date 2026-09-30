import { ServiceContainer } from '../services/ServiceContainer';
import { ErrorHandler } from '../common/ErrorHandler';
import { common } from '@kit.AbilityKit';
import { BridgeError } from '../common/BridgeError';
import { FoundationCard } from '../components/FoundationCard';
import { ActionCard } from '../components/ActionCard';
import { StatusBadge } from '../components/StatusBadge';
import { DemoTask, isActiveTask } from '../models/InteractionModels';
import { UiFeedback } from '../common/UiFeedback';
import { TaskStore } from '../viewmodel/TaskStore';
import { registryMetadata } from '../generated/RegistryData';
import { FormatRegistry } from '../services/FormatRegistry';
import { FoundationViewModel } from '../viewmodel/FoundationViewModel';

@Entry
@Preview
@Component
struct Index {
  private services: ServiceContainer = ServiceContainer.current();
  @State nativeState: string = '正在检测原生连接，交互演示可用';
  @State availableCount: number = 0;
  @State capabilityLabel: string = '检查中';
  @State checking: boolean = false;
  @State formatCount: number = this.services.registry.listFormats().length;
  @State routeCount: number = this.services.registry.listPlannedRoutes().length;
  @State tasks: DemoTask[] = [];
  private viewModel: FoundationViewModel = new FoundationViewModel(this.services.registry, this.services.native);
  private store: TaskStore = this.services.tasks;
  private token: number = -1;
  private active: boolean = false;

  aboutToAppear(): void {
    this.observeTasks();
    this.inspect(false);
  }

  onPageShow(): void { this.observeTasks(); }
  onPageHide(): void { this.detach(); }

  private observeTasks(): void {
    this.active = true;
    this.tasks = this.store.snapshot();
    if (this.token === -1) {
      this.token = this.store.subscribe((tasks: DemoTask[]) => { this.tasks = tasks; });
    }
  }

  aboutToDisappear(): void { this.detach(); }

  private detach(): void {
    this.active = false;
    this.store.unsubscribe(this.token); this.token = -1;
  }

  private async inspect(feedback: boolean): Promise<void> {
    if (this.checking) { return; }
    this.checking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (!context) { throw new BridgeError('CONFIG_INVALID', 'REGISTRY_CONTEXT_UNAVAILABLE'); }
      const capabilities = await this.viewModel.inspect(context.resourceManager);
      if (this.active) {
        this.formatCount = this.services.registry.listFormats().length;
        this.routeCount = this.services.registry.listPlannedRoutes().length;
        this.availableCount = this.services.registry.availableRoutes(capabilities).length;
        if (this.availableCount > 0) {
          this.capabilityLabel = 'Native 已连接';
          this.nativeState = `${capabilities.abi} · 本地处理 · ${this.availableCount} 条真实可执行路线`;
        } else {
          this.capabilityLabel = '演示可用';
          this.nativeState = `格式配置已加载 · 演示模式 · ${this.formatCount} 种格式 · ${this.routeCount} 条转换路线`;
        }
        if (feedback) { UiFeedback.toast(this.getUIContext(), '能力检测完成，交互演示可继续使用'); }
      }
    } catch (error) {
      if (this.active) {
        const failure: BridgeError = ErrorHandler.catchBridge(error, 'Index');
        this.formatCount = this.services.registry.listFormats().length;
        this.routeCount = this.services.registry.listPlannedRoutes().length;
        this.availableCount = 0;
        this.capabilityLabel = '演示可用';
        this.nativeState = `原生暂不可用（${failure.code ?? 'INTERNAL_ERROR'}），${this.formatCount} 种格式、${this.routeCount} 条规划路线与演示流程仍可使用`;
        if (feedback) {
          UiFeedback.toast(this.getUIContext(), '当前可使用完整格式目录与演示功能，原生转换暂不可用');
        }
      }
    } finally { this.checking = false; }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text('文档转换工具箱').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).layoutWeight(1)
          Button('?').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_007aff')).width(40).height(40)
            .type(ButtonType.Circle).backgroundColor($r('app.color.palette_edf4ff'))
            .onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/FeatureGuide'); })
        }.width('100%')
        StatusBadge({ text: this.capabilityLabel, color: $r('app.color.palette_007aff') })
        Text('浏览格式、体验流程、管理任务').fontSize(16).fontColor($r('app.color.palette_526077'))
        Row({ space: 12 }) {
          ActionCard({ title: '格式浏览器', symbol: '文', description: '搜索、筛选与格式详情',
            onAction: () => { UiFeedback.open(this.getUIContext(), 'pages/FormatBrowser'); } }).layoutWeight(1)
          ActionCard({ title: '转换执行器', symbol: '⇄', description: '选择格式并体验五阶段演示',
            onAction: () => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage'); } }).layoutWeight(1)
        }.width('100%')
        Row({ space: 12 }) {
          ActionCard({ title: '任务记录', symbol: '≡', description: '查看、暂停、取消或清理记录',
            onAction: () => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); } }).layoutWeight(1)
          ActionCard({ title: '能力检测', symbol: '✓', description: '检测原生连接与真实能力', busy: this.checking,
            onAction: () => { this.inspect(true); } }).layoutWeight(1)
        }.width('100%')
        Row({ space: 12 }) {
          FoundationCard({ label: '格式定义', value: `${this.formatCount}` }).layoutWeight(1)
          FoundationCard({ label: '规划路线', value: `${this.routeCount}` }).layoutWeight(1)
        }.width('100%')
        FoundationCard({ label: '本次会话任务 / 活动任务',
          value: `${this.tasks.length} / ${this.tasks.filter((task: DemoTask) => isActiveTask(task.status)).length}` })
        Text(this.nativeState).fontSize(14).fontColor($r('app.color.palette_172b4d'))
        Text('演示模式不会生成真实文件。当前真实转换引擎尚未接入。').fontSize(14).fontColor($r('app.color.palette_526077'))
        Text(`V1.0 交互开发版 · 配置 ${registryMetadata.configVersion}`).fontSize(12).fontColor($r('app.color.palette_526077'))
      }
      .alignItems(HorizontalAlign.Start)
      .padding(24)
      .width('100%')
      .constraintSize({ maxWidth: 720 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
