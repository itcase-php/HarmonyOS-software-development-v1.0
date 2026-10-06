import { LanguageManager, AppLanguage } from '../common/LanguageManager';
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
import { LanguageToggle } from '../components/LanguageToggle';

@Entry
@Preview
@Component
struct Index {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  private services: ServiceContainer = ServiceContainer.current();
  @State nativeState: string = 'home_checking';
  @State availableCount: number = 0;
  @State capabilityLabel: string = 'checking';
  @State checking: boolean = false;
  @State formatCount: number = this.services.registry.listFormats().length;
  @State routeCount: number = this.services.registry.listPlannedRoutes().length;
  @State tasks: DemoTask[] = [];
  @State nativeArgs: (string | number)[] = [];
  private viewModel: FoundationViewModel = new FoundationViewModel(this.services.registry, this.services.native);
  private store: TaskStore = this.services.tasks;
  private token: number = -1;
  private active: boolean = false;

  aboutToAppear(): void {
    LanguageManager.bind(this.getUIContext().getHostContext());
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
          this.capabilityLabel = 'native_connected';
          this.nativeState = 'home_native'; this.nativeArgs = [capabilities.abi, this.availableCount];
        } else {
          this.capabilityLabel = 'demo_available';
          this.nativeState = 'home_demo'; this.nativeArgs = [this.formatCount, this.routeCount];
        }
        if (feedback) { UiFeedback.toast(this.getUIContext(), this.tr('home_checked')); }
      }
    } catch (error) {
      if (this.active) {
        const failure: BridgeError = ErrorHandler.catchBridge(error, 'Index');
        this.formatCount = this.services.registry.listFormats().length;
        this.routeCount = this.services.registry.listPlannedRoutes().length;
        this.availableCount = 0;
        this.capabilityLabel = 'demo_available';
        this.nativeState = 'home_native_unavailable'; this.nativeArgs = [failure.code ?? 'INTERNAL_ERROR', this.formatCount, this.routeCount];
        if (feedback) {
          UiFeedback.toast(this.getUIContext(), this.tr('home_fallback'));
        }
      }
    } finally { this.checking = false; }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(this.tr('home_title')).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).layoutWeight(1)
          Button('?').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_007aff')).width(40).height(40)
            .type(ButtonType.Circle).backgroundColor($r('app.color.palette_edf4ff'))
            .accessibilityText(this.tr('help_a11y'))
            .onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/FeatureGuide'); })
          LanguageToggle()
        }.width('100%')
        StatusBadge({ text: this.tr(this.capabilityLabel), color: $r('app.color.palette_007aff') })
        Text(this.tr('home_subtitle')).fontSize(16).fontColor($r('app.color.palette_526077'))
        Row({ space: 12 }) {
          ActionCard({ title: this.tr('browser_title_short'), symbol: this.tr('browser_symbol'), description: this.tr('home_browser_description'),
            onAction: () => { UiFeedback.open(this.getUIContext(), 'pages/FormatBrowser'); } }).layoutWeight(1)
          ActionCard({ title: this.tr('converter_title'), symbol: '⇄', description: this.tr('home_converter_description'),
            onAction: () => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage'); } }).layoutWeight(1)
        }.width('100%')
        Row({ space: 12 }) {
          ActionCard({ title: this.tr('history_title'), symbol: '≡', description: this.tr('home_history_description'),
            onAction: () => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); } }).layoutWeight(1)
          ActionCard({ title: this.tr('home_capabilities'), symbol: '✓', description: this.tr('home_capabilities_description'), busy: this.checking,
            onAction: () => { this.inspect(true); } }).layoutWeight(1)
        }.width('100%')
        Row({ space: 12 }) {
          FoundationCard({ label: this.tr('home_formats'), value: `${this.formatCount}` }).layoutWeight(1)
          FoundationCard({ label: this.tr('home_routes'), value: `${this.routeCount}` }).layoutWeight(1)
        }.width('100%')
        FoundationCard({ label: this.tr('home_tasks'),
          value: `${this.tasks.length} / ${this.tasks.filter((task: DemoTask) => isActiveTask(task.status)).length}` })
        Text(this.tr(this.nativeState, this.nativeArgs)).fontSize(14).fontColor($r('app.color.palette_172b4d'))
        Text(this.tr('home_gate_notice')).fontSize(14).fontColor($r('app.color.palette_526077'))
        Text(this.tr('home_version', [registryMetadata.configVersion])).fontSize(12).fontColor($r('app.color.palette_526077'))
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
