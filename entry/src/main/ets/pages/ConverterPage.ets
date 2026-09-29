import { RegistryFormat, ConversionRouteDefinition } from '../models/RegistryTypes';
import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { ConverterNavigationParams, DemoTask, DemoSubmission, FidelitySelection, FidelitySettingsVM, IntentChoice,
  taskStatusLabel, taskStatusColor, isActiveTask } from '../models/InteractionModels';
import { FormatRegistry } from '../services/FormatRegistry';
import { ConversionPlanner } from '../viewmodel/ConversionPlanner';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';
import { TaskStore } from '../viewmodel/TaskStore';
import { BridgeError } from '../common/BridgeError';
import { UiFeedback } from '../common/UiFeedback';
import { PageHeader } from '../components/PageHeader';
import { StatusBadge } from '../components/StatusBadge';
import { FidelitySettingsCard } from '../components/FidelitySettingsCard';
import { FidelityText } from '../common/FidelityText';
import { FidelityReportCard } from '../components/FidelityReportCard';
import { RegistryUi } from '../common/RegistryUi';

@Entry
@Preview
@Component
struct ConverterPage {
  @State sourceId: string = '';
  @State targetId: string = '';
  @State routeId: string = '';
  @State fileName: string = '';
  @State sourceIndex: number = 0;
  @State targetIndex: number = 0;
  @State routeIndex: number = 0;
  @State approved: boolean = false;
  @State fidelityVM: FidelitySettingsVM = new FidelitySettingsVM();
  @State sourceChoices: SelectOption[] = [];
  @State targetChoices: SelectOption[] = [];
  @State routeChoices: SelectOption[] = [];
  @State errorText: string = '';
  @State taskId: string = '';
  @State visibleTasks: DemoTask[] = [];
  @State working: boolean = false;
  @State confirming: boolean = false;
  @State inlineConfirmationText: string = '';
  @State registryReady: boolean = true;
  @State registryLoading: boolean = false;
  private formats: RegistryFormat[] = FormatRegistry.listFormats();
  private targetFormats: RegistryFormat[] = [];
  private activeRoutes: ConversionRouteDefinition[] = [];
  private supportedIntents: IntentChoice[] = [];
  private tiers: FidelityTier[] = ['extreme', 'standard', 'compatible'];
  private store: TaskStore = TaskStore.shared();
  private token: number = -1;
  private pendingSubmission: DemoSubmission | undefined = undefined;

  aboutToAppear(): void {
    this.observeTasks();
    this.loadFormats();
  }

  private async loadFormats(): Promise<void> {
    if (this.registryLoading) { return; }
    this.initializeSelections();
    this.registryLoading = true;
    try {
      await RegistryUi.ensure(this.getUIContext());
      this.formats = FormatRegistry.listFormats(); this.registryReady = true;
      this.errorText = ''; this.syncInteractivity();
      this.initializeSelections();
    } catch (_) {
      this.registryReady = false;
      this.errorText = FidelityText.read(this.getUIContext(), $r('app.string.registry_error'));
      this.syncInteractivity();
    } finally { this.registryLoading = false; }
  }

  private initializeSelections(): void {
    if (this.sourceId.length !== 0) { return; }
    this.sourceChoices = this.formats.map((format: RegistryFormat): SelectOption => ({
      value: `${format.displayName} (${format.id})`
    }));
    this.fidelityVM.tierChoices = this.tiers.map((tier: FidelityTier): SelectOption => ({ value: FidelityText.tier(this.getUIContext(), tier) }));
    let source = this.formats.findIndex((format: RegistryFormat) => ConversionPlanner.targets(format.id).length > 0);
    try {
      const params = this.getUIContext().getRouter().getParams() as ConverterNavigationParams;
      if (params && params.sourceFormatId) {
        const index = this.formats.findIndex((format: RegistryFormat) => format.id === params.sourceFormatId);
        if (index >= 0) { source = index; }
      }
      if (params && params.qualityMode && FidelityPolicy.isQualityMode(params.qualityMode)) {
        this.fidelityVM.qualityMode = params.qualityMode;
      }
    } catch (_) { /* Standalone preview has no navigation parameters. */ }
    this.selectSource(Math.max(0, source));
  }

  aboutToDisappear(): void { this.detach(); }
  onPageShow(): void { this.observeTasks(); }
  onPageHide(): void { this.detach(); }

  private detach(): void {
    this.store.unsubscribe(this.token); this.token = -1;
    this.cancelConfirmation();
  }
  private receiveTasks(tasks: DemoTask[]): void {
    this.visibleTasks = tasks.filter((task: DemoTask) => task.id === this.taskId);
    const task = this.visibleTasks[0];
    this.working = task !== undefined && isActiveTask(task.status);
    this.syncInteractivity();
  }
  private observeTasks(): void {
    this.receiveTasks(this.store.snapshot());
    if (this.token === -1) {
      this.token = this.store.subscribe((tasks: DemoTask[]) => { this.receiveTasks(tasks); });
    }
  }

  private syncInteractivity(): void {
    const vm = this.fidelityVM.clone();
    vm.interactive = this.registryReady && !this.working && !this.confirming;
    this.fidelityVM = vm;
  }

  private selectSource(index: number): void {
    const format = this.formats[index];
    if (!format) { return; }
    this.sourceIndex = index; this.sourceId = format.id;
    this.fileName = `示例文档.${format.extensions[0]}`;
    this.targetFormats = ConversionPlanner.targets(this.sourceId);
    this.targetChoices = this.targetFormats.map((target: RegistryFormat): SelectOption => ({
      value: `${target.displayName} (${target.id})`
    }));
    this.selectTarget(0);
  }
  private selectTarget(index: number): void {
    const target = this.targetFormats[index];
    this.targetIndex = index; this.targetId = target ? target.id : '';
    const first = ConversionPlanner.routes(this.sourceId, this.targetId)[0];
    if (first) {
      this.fidelityVM.requestedIntent = first.intent;
      this.fidelityVM.requestedTier = first.fidelityTier;
    }
    this.refreshRoutes();
  }

  // All option arrays and route descriptions are prepared here, outside build().
  private refreshRoutes(preferredId: string = ''): void {
    const allRoutes = ConversionPlanner.routes(this.sourceId, this.targetId);
    const intents: IntentChoice[] = [];
    for (const route of allRoutes) {
      if (!intents.some((choice: IntentChoice) => choice.value === route.intent)) {
        intents.push({ value: route.intent, label: FidelityText.intent(this.getUIContext(), route.intent) });
      }
    }
    this.supportedIntents = intents;
    this.fidelityVM.intentChoices = intents.map((choice: IntentChoice): SelectOption => ({ value: choice.label }));
    this.fidelityVM.intentIndex = Math.max(0, intents.findIndex((choice: IntentChoice) => choice.value === this.fidelityVM.requestedIntent));
    this.fidelityVM.tierIndex = Math.max(0, this.tiers.findIndex((tier: FidelityTier) => tier === this.fidelityVM.requestedTier));
    this.fidelityVM.intentText = FidelityText.intent(this.getUIContext(), this.fidelityVM.requestedIntent);
    this.fidelityVM.tierText = FidelityText.tier(this.getUIContext(), this.fidelityVM.requestedTier);
    this.fidelityVM.qualitySummary = FidelityText.read(this.getUIContext(), $r('app.string.quality_duration'),
      [FidelityText.quality(this.getUIContext(), this.fidelityVM.qualityMode), (FidelityPolicy.durationMs(this.fidelityVM.qualityMode) / 1000).toString()]);
    this.fidelityVM.selectionSummary = FidelityText.read(this.getUIContext(), $r('app.string.fidelity_selection_summary'),
      [this.fidelityVM.qualitySummary, this.fidelityVM.tierText]);
    this.activeRoutes = ConversionPlanner.routes(this.sourceId, this.targetId, this.fidelityVM.qualityMode,
      this.fidelityVM.requestedIntent, this.fidelityVM.requestedTier);
    this.routeChoices = this.activeRoutes.map((route: ConversionRouteDefinition): SelectOption => ({
      value: FidelityText.read(this.getUIContext(), $r('app.string.route_choice'), [
        FidelityText.read(this.getUIContext(), route.pathMode === 'direct' ? $r('app.string.path_direct') : $r('app.string.path_relay')),
        FidelityText.tier(this.getUIContext(), route.fidelityTier), route.id])
    }));
    const preferred = this.activeRoutes.findIndex((route: ConversionRouteDefinition) => route.id === preferredId);
    this.selectRoute(preferred >= 0 ? preferred : 0);
    this.errorText = '';
    this.fidelityVM = this.fidelityVM.clone();
  }
  private selectRoute(index: number): void {
    const route = this.activeRoutes[index];
    this.routeIndex = index; this.routeId = route ? route.id : '';
    this.approved = false;
    if (route) {
      this.fidelityVM.requestedIntent = route.intent;
      this.fidelityVM.routeDescription = FidelityText.read(this.getUIContext(), $r('app.string.route_description'), [
        FidelityText.tier(this.getUIContext(), route.fidelityTier),
        FidelityText.read(this.getUIContext(), route.pathMode === 'direct' ? $r('app.string.path_direct') : $r('app.string.path_relay')),
        FidelityText.intent(this.getUIContext(), route.intent)]);
      this.fidelityVM.routeNotice = FidelityText.read(this.getUIContext(), route.requiresUserApproval ?
        $r('app.string.route_approval_notice') : $r('app.string.route_limit_notice'));
    } else {
      this.fidelityVM.routeDescription = FidelityText.read(this.getUIContext(), $r('app.string.route_missing'));
      this.fidelityVM.routeNotice = FidelityText.read(this.getUIContext(), $r('app.string.route_missing_notice'));
    }
    this.fidelityVM.routeAvailable = route !== undefined;
    this.fidelityVM = this.fidelityVM.clone();
  }
  private selectIntent(index: number): void {
    const intent = this.supportedIntents[index];
    if (intent) { this.fidelityVM.requestedIntent = intent.value; this.refreshRoutes(); }
  }
  private selectTier(index: number): void {
    const tier = this.tiers[index];
    if (tier) { this.fidelityVM.requestedTier = tier; this.refreshRoutes(); }
  }
  private selectQuality(mode: QualityMode): void {
    if (!this.registryReady || this.working || this.confirming) { return; }
    this.fidelityVM.qualityMode = mode; this.refreshRoutes(this.routeId);
  }

  private useExample(): void {
    const source = this.formats[this.sourceIndex];
    if (source) {
      this.fileName = `示例文档.${source.extensions[0]}`;
      this.errorText = ''; UiFeedback.toast(this.getUIContext(), '已填入演示名称，不会读取设备文件');
    }
  }

  private selection(): FidelitySelection {
    return { qualityMode: this.fidelityVM.qualityMode, requestedIntent: this.fidelityVM.requestedIntent, requestedTier: this.fidelityVM.requestedTier };
  }
  private showError(error: Error): void {
    const failure = error as BridgeError;
    switch (failure.reason) {
      case 'DEMO_FILENAME_INVALID': this.errorText = '请输入有效文件名，不要包含目录路径或特殊字符'; break;
      case 'DEMO_EXTENSION_REQUIRED': this.errorText = '文件名需要扩展名，例如“报告.pdf”'; break;
      case 'DEMO_EXTENSION_MISMATCH': this.errorText = '扩展名与源格式不一致，请修改或填入示例'; break;
      case 'DRM_BLOCKED': this.errorText = '受保护格式已阻止演示'; break;
      case 'DEMO_APPROVAL_REQUIRED': this.errorText = '请先勾选同意所选路线的兼容降级'; break;
      case 'FIDELITY_INTENT_MISMATCH': this.errorText = '所选转换意图与路线不一致'; break;
      case 'FIDELITY_TIER_UNAVAILABLE': this.errorText = '当前路线不能满足最低保真等级，不会自动降级'; break;
      default: this.errorText = '此组合暂不能演示，请重新选择路线与保真设置'; break;
    }
    UiFeedback.toast(this.getUIContext(), this.errorText);
  }
  private start(): void {
    if (!this.registryReady || this.working || this.confirming) { return; }
    try {
      const route = this.activeRoutes.find((item: ConversionRouteDefinition) => item.id === this.routeId);
      if (!route) { throw new BridgeError('UNSUPPORTED_FORMAT', 'DEMO_ROUTE_NOT_FOUND'); }
      const name = ConversionPlanner.validateFileName(this.fileName, this.sourceId);
      const fidelity = this.selection();
      FidelityPolicy.validate(route, fidelity);
      if (route.requiresUserApproval && !this.approved) {
        throw new BridgeError('INVALID_REQUEST', 'DEMO_APPROVAL_REQUIRED');
      }
      this.pendingSubmission = { fileName: name, sourceId: this.sourceId, targetId: this.targetId,
        routeId: route.id, approved: this.approved, fidelity: fidelity };
      this.errorText = '';
      this.confirming = true; this.syncInteractivity();
      const message = `文件：${name}\n格式：${this.sourceId} → ${this.targetId}\n质量：${this.fidelityVM.qualitySummary}\n意图：${this.fidelityVM.intentText}\n最低期望：${this.fidelityVM.tierText}\n${this.fidelityVM.routeDescription}\n路线：${route.id}\n降级配置：${route.allowedDegradations.join('、') || '无'}\n\n演示不会读取文件或产生真实保真结果。`;
      try {
        this.getUIContext().showAlertDialog({
          title: '确认保真度配置（演示）', message: message, autoCancel: true,
          primaryButton: { value: '返回修改', action: () => { this.cancelConfirmation(); } },
          secondaryButton: { value: '确认开始演示', action: () => { this.beginConfirmed(); } },
          cancel: () => { this.cancelConfirmation(); }
        });
      } catch (_) {
        // Previewer fallback: keep the same confirmation, never start automatically.
        this.inlineConfirmationText = message;
      }
    } catch (error) { this.showError(error as Error); }
  }
  private cancelConfirmation(): void {
    this.confirming = false; this.inlineConfirmationText = ''; this.pendingSubmission = undefined; this.syncInteractivity();
  }
  private beginConfirmed(): void {
    const submission = this.pendingSubmission;
    if (!submission || this.working) { return; }
    this.cancelConfirmation();
    try {
      const task = this.store.enqueue(submission.fileName, submission.sourceId, submission.targetId,
        submission.routeId, submission.approved, submission.fidelity);
      this.taskId = task.id; this.receiveTasks(this.store.snapshot());
      UiFeedback.toast(this.getUIContext(), '已按确认的保真度配置开始演示');
    } catch (error) { this.showError(error as Error); }
  }

  @Builder
  taskResult(task: DemoTask) {
    Column({ space: 12 }) {
      Text('⑤ 任务进度与结果').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#172B4D')
      StatusBadge({ text: taskStatusLabel(task.status), color: taskStatusColor(task.status) })
      Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%').color('#007AFF')
      Text(`${task.progress}% · ${task.stage}`).fontSize(14).fontColor('#526077')
      Text(`${FidelityPolicy.qualityLabel(task.qualityMode)} · ${FidelityPolicy.intentLabel(task.requestedIntent)} · 最低${FidelityPolicy.tierLabel(task.requestedTier)}`)
        .fontSize(13).fontColor('#526077')
      if (task.status === 'running') {
        Button('暂停演示').onClick(() => { this.store.pause(task.id); })
      } else if (task.status === 'paused') {
        Button('继续演示').onClick(() => { this.store.resume(task.id); })
      }
      if (isActiveTask(task.status)) {
        Button('取消演示').backgroundColor('#E5ECF5').fontColor('#172B4D')
          .onClick(() => { this.store.cancel(task.id); UiFeedback.toast(this.getUIContext(), '演示已取消'); })
      }
      if (task.status === 'completed') {
        Text(task.resultLabel).fontSize(15).fontColor('#167644')
        Text(`演示耗时 ${(task.elapsedMs / 1000).toFixed(1)} 秒；未执行真实转换或保真检测。`)
          .fontSize(14).fontColor('#526077')
        FidelityReportCard({ report: task.fidelityReport })
      }
      Button('查看任务记录').onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); })
    }.padding(16).backgroundColor('#FFFFFF').borderRadius(16).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: '转换执行器', subtitle: '选择格式、设置保真策略、确认后体验任务流程' })
        StatusBadge({ text: '演示模式 · 不生成文件', color: '#A65C00' })
        if (!this.registryReady) {
          Text(this.registryLoading ? $r('app.string.registry_loading') : $r('app.string.registry_error'))
          Button($r('app.string.registry_retry')).enabled(!this.registryLoading).onClick(() => { this.loadFormats(); })
        }
        Text('真实转换引擎尚未接入。保真设置与报告均用于交互演示，不是文件质量的测量结果。')
          .fontSize(14).fontColor('#526077')
        Column({ space: 12 }) {
          Text('① 选择源格式').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#172B4D')
          Select(this.sourceChoices).selected(this.sourceIndex).value(this.sourceId.toUpperCase()).width('100%')
            .accessibilityText($r('app.string.a11y_source')).accessibilityDescription($r('app.string.a11y_source'))
            .enabled(!this.working && !this.confirming).onSelect((index: number) => { this.selectSource(index); })
          Text('② 选择目标与路线').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#172B4D')
          if (this.targetChoices.length > 0) {
            Select(this.targetChoices).selected(this.targetIndex).value(this.targetId.toUpperCase()).width('100%')
              .accessibilityText($r('app.string.a11y_target')).accessibilityDescription($r('app.string.a11y_target'))
              .enabled(!this.working && !this.confirming).onSelect((index: number) => { this.selectTarget(index); })
          } else {
            Text('此源格式暂无单文件规划路线，请切换源格式。').fontSize(14).fontColor('#C53030')
          }
          FidelitySettingsCard({ vm: this.fidelityVM,
            onSelectQuality: (mode: QualityMode) => { this.selectQuality(mode); },
            onSelectIntent: (index: number) => { this.selectIntent(index); },
            onSelectTier: (index: number) => { this.selectTier(index); } })
          if (this.routeChoices.length > 0) {
            Select(this.routeChoices).selected(this.routeIndex).value(this.routeId).width('100%')
              .accessibilityText($r('app.string.a11y_route')).accessibilityDescription(this.fidelityVM.routeDescription)
              .enabled(!this.working && !this.confirming).onSelect((index: number) => { this.selectRoute(index); })
          }
          Row({ space: 8 }) {
            Checkbox({ name: 'approve-demo' }).select(this.approved).enabled(!this.working && !this.confirming)
              .accessibilityText($r('app.string.a11y_approval')).accessibilityDescription(this.fidelityVM.routeNotice)
              .onChange((value: boolean) => { this.approved = value; })
            Text('同意演示所选路线配置的兼容降级').fontSize(13).fontColor('#526077').layoutWeight(1)
          }
          Text('③ 模拟选择文件').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#172B4D')
          TextInput({ text: this.fileName, placeholder: '填写文件名及扩展名' }).maxLength(180)
            .accessibilityText($r('app.string.a11y_filename')).accessibilityDescription($r('app.string.a11y_filename'))
            .enabled(!this.working && !this.confirming).onChange((value: string) => { this.fileName = value; this.errorText = ''; })
          Button('填入示例文件名').enabled(!this.working && !this.confirming).backgroundColor('#E5ECF5').fontColor('#172B4D')
            .accessibilityText('填入示例文件名').accessibilityDescription('只设置演示名称，不读取文件')
            .onClick(() => { this.useExample(); })
          Text('只填写演示名称，不读取或上传设备文件。').fontSize(12).fontColor('#526077')
          if (this.errorText.length > 0) { Text(this.errorText).fontSize(14).fontColor('#C53030') }
          Button(this.working ? '演示任务进行中' : this.confirming ? '等待配置确认' : '④ 确认配置并开始演示')
            .accessibilityText($r('app.string.a11y_start')).accessibilityDescription(this.fidelityVM.selectionSummary)
            .enabled(!this.working && !this.confirming && this.routeId.length > 0).width('100%').backgroundColor('#007AFF')
            .onClick(() => { this.start(); })
          if (this.inlineConfirmationText.length > 0) {
            Text(this.inlineConfirmationText).fontSize(14).fontColor('#172B4D')
            Button('确认开始演示').onClick(() => { this.beginConfirmed(); })
            Button('返回修改').onClick(() => { this.cancelConfirmation(); })
          }
        }.width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(16).alignItems(HorizontalAlign.Start)
        ForEach(this.visibleTasks, (task: DemoTask) => {
          this.taskResult(task)
        }, (task: DemoTask) => `${task.id}-${task.status}-${task.progress}-${task.elapsedMs}`)
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor('#F2F5FA')
  }
}
