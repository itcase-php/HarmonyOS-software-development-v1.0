import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { ServiceContainer } from '../services/ServiceContainer';
import { DemoTask, taskStatusLabel, taskStatusColor, isActiveTask } from '../models/InteractionModels';
import { UiFeedback } from '../common/UiFeedback';
import { StatusBadge } from './StatusBadge';
import { FidelityReportCard } from './FidelityReportCard';

@Component
export struct ConversionProgressPanel {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @ObjectLink model: ConversionStatusVM;
  @Consume('services') services: ServiceContainer;
  @Builder
  nativeInputResult(task: DemoTask) {
    Column({ space: 10 }) {
      StatusBadge({ text: this.tr(taskStatusLabel(task.status, task.mode)), color: taskStatusColor(task.status) })
      Text(task.fileName).fontSize(16)
      Text(LanguageManager.stage(task.stage, task.stageArgs, this.language)).fontSize(13).fontColor($r('app.color.palette_526077'))
      if (task.error.length > 0) { Text(this.model.inputFailure(task.error.substring(task.error.indexOf(':') + 1))).fontColor($r('app.color.palette_c53030')) }
      if (isActiveTask(task.status)) {
        Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%')
        Button(this.tr($r('app.string.input_cancel_task'))).onClick(() => { this.services.tasks.cancel(task.id); })
      }
      if (task.status === 'completed') { Text(this.tr(task.resultLabel, task.resultArgs)); FidelityReportCard({ report: task.fidelityReport, mode: task.mode }) }
      Button(this.tr($r('app.string.input_task_history'))).onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); })
    }.padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).width('100%')
  }

  @Builder
  taskResult(task: DemoTask) {
    Column({ space: 12 }) {
      Text(this.tr('progress_title')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
      StatusBadge({ text: this.tr(taskStatusLabel(task.status)), color: taskStatusColor(task.status) })
      Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%').color($r('app.color.palette_007aff'))
      Text(`${task.progress}% · ${LanguageManager.stage(task.stage, task.stageArgs, this.language)}`).fontSize(14).fontColor($r('app.color.palette_526077'))
      Text(this.tr('task_fidelity', [LanguageManager.quality(task.qualityMode), LanguageManager.intent(task.requestedIntent), LanguageManager.tier(task.requestedTier)]))
        .fontSize(13).fontColor($r('app.color.palette_526077'))
      if (task.status === 'running') {
        Button(this.tr('pause_demo')).onClick(() => { this.services.tasks.pause(task.id); })
      } else if (task.status === 'paused') {
        Button(this.tr('resume_demo')).onClick(() => { this.services.tasks.resume(task.id); })
      }
      if (isActiveTask(task.status)) {
        Button(this.tr('cancel_demo')).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
          .onClick(() => { this.services.tasks.cancel(task.id); UiFeedback.toast(this.getUIContext(), this.tr('demo_cancelled')); })
      }
      if (task.status === 'completed') {
        Text(this.tr(task.resultLabel, task.resultArgs)).fontSize(15).fontColor($r('app.color.palette_167644'))
        Text(this.tr('demo_elapsed_notice', [(task.elapsedMs / 1000).toFixed(1)]))
          .fontSize(14).fontColor($r('app.color.palette_526077'))
        FidelityReportCard({ report: task.fidelityReport })
      }
      Button(this.tr('history_view')).onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); })
    }.padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      ForEach(this.model.visibleTasks, (task: DemoTask) => {
        if (task.mode === 'native') { this.nativeInputResult(task) } else { this.taskResult(task) }
      }, (task: DemoTask) => `${task.id}-${task.status}-${task.progress}-${task.elapsedMs}`)
    }.width('100%')
  }
}
@Preview
@Component
struct ConversionProgressPanelPreview {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Provide('services') services: ServiceContainer = new ServiceContainer();
  @State model: ConversionStatusVM = new ConversionStatusVM(this.services.tasks);
  build() { ConversionProgressPanel({ model: this.model }) }
}
