import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { ServiceContainer } from '../services/ServiceContainer';
import { DemoTask, taskStatusLabel, taskStatusColor, isActiveTask } from '../models/InteractionModels';
import { TaskStore } from '../viewmodel/TaskStore';
import { UiFeedback } from '../common/UiFeedback';
import { PageHeader } from '../components/PageHeader';
import { StatusBadge } from '../components/StatusBadge';
import { FormatTag } from '../components/FormatTag';
import { FidelityReportCard } from '../components/FidelityReportCard';
import { common } from '@kit.AbilityKit';
import { ArtifactDelivery } from '../services/ArtifactDelivery';

@Entry
@Preview
@Component
struct TaskHistory {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  private services: ServiceContainer = ServiceContainer.current();
  @State tasks: DemoTask[] = [];
  private store: TaskStore = this.services.tasks;
  private statusText: ConversionStatusVM = new ConversionStatusVM();
  private delivery: ArtifactDelivery = new ArtifactDelivery(this.store, this.services.native);
  private token: number = -1;

  aboutToAppear(): void {
    LanguageManager.bind(this.getUIContext().getHostContext());
    this.observeTasks();
  }
  onPageShow(): void { this.observeTasks(); }
  onPageHide(): void { this.store.unsubscribe(this.token); this.token = -1; }
  private observeTasks(): void {
    this.tasks = this.store.snapshot();
    if (this.token === -1) {
      this.token = this.store.subscribe((tasks: DemoTask[]) => { this.tasks = tasks; });
    }
  }
  aboutToDisappear(): void { this.store.unsubscribe(this.token); this.token = -1; }

  private clear(): void {
    const count = this.store.clearFinished();
    UiFeedback.toast(this.getUIContext(), this.tr('history_cleared', [count]));
  }

  private async savePdf(id: string): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved: boolean = await this.delivery.save(id, context);
      UiFeedback.toast(this.getUIContext(), saved ? this.tr('pdf_saved') : this.tr('save_cancelled'));
    } catch (error) { UiFeedback.toast(this.getUIContext(), this.tr('save_failed')); }
  }

  private async sharePdf(id: string): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.delivery.share(id, context);
    } catch (error) { UiFeedback.toast(this.getUIContext(), this.tr('share_failed')); }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: this.tr('history_title'), subtitle: this.tr('history_subtitle') })
        Row({ space: 12 }) {
          Text(this.tr('history_count', [this.tasks.length])).fontSize(16).fontColor($r('app.color.palette_526077')).layoutWeight(1)
          Button(this.tr('history_clear')).fontSize(13)
            .accessibilityText(this.tr('history_clear')).accessibilityDescription(this.tr('history_keep_active'))
            .enabled(this.tasks.some((task: DemoTask) => !isActiveTask(task.status)))
            .onClick(() => { this.clear(); })
        }.width('100%')
        if (this.tasks.length === 0) {
          Column({ space: 12 }) {
            Text('≡').fontSize(44).fontColor($r('app.color.palette_526077'))
            Text(this.tr('history_empty')).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
            Text(this.tr('history_empty_tip')).fontSize(14).fontColor($r('app.color.palette_526077'))
            Button(this.tr('demo_start')).onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage'); })
          }.width('100%').padding(32).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16)
        }
        ForEach(this.tasks, (task: DemoTask) => {
          Column({ space: 10 }) {
            Text(task.fileName).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d')).maxLines(2)
            Row({ space: 8 }) {
              FormatTag({ formatId: task.sourceFormat })
              Text('→').fontColor($r('app.color.palette_526077'))
              FormatTag({ formatId: task.targetFormat })
              Blank()
              StatusBadge({ text: this.tr(taskStatusLabel(task.status, task.mode)), color: taskStatusColor(task.status) })
            }.width('100%')
            Text(new Date(task.createdAtMs).toLocaleString(this.language === 'zh' ? 'zh-CN' : 'en-US')).fontSize(12).fontColor($r('app.color.palette_526077'))
            Text(this.tr('task_elapsed', [LanguageManager.stage(task.stage, task.stageArgs, this.language), (task.elapsedMs / 1000).toFixed(1)])).fontSize(13).fontColor($r('app.color.palette_526077'))
            Text(this.tr('task_fidelity', [LanguageManager.quality(task.qualityMode), LanguageManager.intent(task.requestedIntent), LanguageManager.tier(task.requestedTier)]))
              .fontSize(13).fontColor($r('app.color.palette_526077'))
            if (isActiveTask(task.status)) {
              Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%').color($r('app.color.palette_007aff'))
              Row({ space: 10 }) {
                if (task.status === 'running' && task.mode === 'demo') {
                  Button(this.tr('pause')).fontSize(13).accessibilityText(this.tr('pause_task')).accessibilityDescription(task.fileName)
                    .onClick(() => { this.store.pause(task.id); })
                }
                if (task.status === 'paused') {
                  Button(this.tr('resume')).fontSize(13).accessibilityText(this.tr('resume_task')).accessibilityDescription(task.fileName)
                    .onClick(() => { this.store.resume(task.id); })
                }
                Button(this.tr('cancel')).fontSize(13).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
                  .accessibilityText(this.tr('cancel_task')).accessibilityDescription(task.fileName)
                  .onClick(() => { this.store.cancel(task.id); UiFeedback.toast(this.getUIContext(), this.tr('cancel_requested')); })
              }
            }
            if (task.resultLabel.length > 0) {
              Text(this.tr(task.resultLabel, task.resultArgs)).fontSize(14).fontColor($r('app.color.palette_167644'))
            }
            if (task.status === 'completed' && task.fidelityReport) {
              FidelityReportCard({ report: task.fidelityReport, mode: task.mode })
            }
            if (task.mode === 'native' && task.status === 'completed' && task.targetFormat === 'pdf' &&
              this.store.hasDeliverable(task.id)) {
              Row({ space: 10 }) {
                Button(this.tr('save_pdf')).fontSize(13).accessibilityText(this.tr('save_pdf_a11y'))
                  .onClick(() => { this.savePdf(task.id); })
                Button(this.tr('share_pdf')).fontSize(13).accessibilityText(this.tr('share_pdf')).id(`share-${task.id}`)
                  .onClick(() => { this.sharePdf(task.id); })
              }
            }
            if (task.mode === 'native' && task.status === 'completed' && !task.fidelityReport) {
              Text(this.tr($r('app.string.report_missing'))).fontSize(13).fontColor($r('app.color.palette_526077'))
            }
            if (task.error.length > 0) { Text(this.tr(this.statusText.inputFailure(task.error.substring(task.error.indexOf(':') + 1)))).fontSize(13).fontColor($r('app.color.palette_c53030')) }
            Text(task.mode === 'demo' ? this.tr('record_demo') :
              task.status === 'completed' ?
                this.store.exportSnapshot(task.id).some((record) => record.state === 'exported') ?
                  this.tr('record_saved') : this.tr('record_internal') :
                this.tr('record_no_output'))
              .fontSize(12).fontColor($r('app.color.palette_526077'))
          }.width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).alignItems(HorizontalAlign.Start)
        }, (task: DemoTask) => `${task.id}-${task.status}-${task.progress}-${task.elapsedMs}-${task.resultLabel}`)
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
