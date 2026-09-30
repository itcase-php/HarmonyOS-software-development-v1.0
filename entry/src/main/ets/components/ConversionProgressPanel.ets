import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { ServiceContainer } from '../services/ServiceContainer';
import { DemoTask, taskStatusLabel, taskStatusColor, isActiveTask } from '../models/InteractionModels';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';
import { UiFeedback } from '../common/UiFeedback';
import { StatusBadge } from './StatusBadge';
import { FidelityReportCard } from './FidelityReportCard';

@Component
export struct ConversionProgressPanel {
  @ObjectLink model: ConversionStatusVM;
  @Consume('services') services: ServiceContainer;
  @Builder
  nativeInputResult(task: DemoTask) {
    Column({ space: 10 }) {
      StatusBadge({ text: taskStatusLabel(task.status, task.mode), color: taskStatusColor(task.status) })
      Text(task.fileName).fontSize(16)
      Text(task.stage).fontSize(13).fontColor($r('app.color.palette_526077'))
      if (task.error.length > 0) { Text(this.model.inputFailure(task.error.substring(task.error.indexOf(':') + 1))).fontColor($r('app.color.palette_c53030')) }
      if (isActiveTask(task.status)) {
        Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%')
        Button($r('app.string.input_cancel_task')).onClick(() => { this.services.tasks.cancel(task.id); })
      }
      if (task.status === 'completed') { Text(task.resultLabel); FidelityReportCard({ report: task.fidelityReport }) }
      Button($r('app.string.input_task_history')).onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); })
    }.padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).width('100%')
  }

  @Builder
  taskResult(task: DemoTask) {
    Column({ space: 12 }) {
      Text('⑤ 任务进度与结果').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
      StatusBadge({ text: taskStatusLabel(task.status), color: taskStatusColor(task.status) })
      Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%').color($r('app.color.palette_007aff'))
      Text(`${task.progress}% · ${task.stage}`).fontSize(14).fontColor($r('app.color.palette_526077'))
      Text(`${FidelityPolicy.qualityLabel(task.qualityMode)} · ${FidelityPolicy.intentLabel(task.requestedIntent)} · 最低${FidelityPolicy.tierLabel(task.requestedTier)}`)
        .fontSize(13).fontColor($r('app.color.palette_526077'))
      if (task.status === 'running') {
        Button('暂停演示').onClick(() => { this.services.tasks.pause(task.id); })
      } else if (task.status === 'paused') {
        Button('继续演示').onClick(() => { this.services.tasks.resume(task.id); })
      }
      if (isActiveTask(task.status)) {
        Button('取消演示').backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
          .onClick(() => { this.services.tasks.cancel(task.id); UiFeedback.toast(this.getUIContext(), '演示已取消'); })
      }
      if (task.status === 'completed') {
        Text(task.resultLabel).fontSize(15).fontColor($r('app.color.palette_167644'))
        Text(`演示耗时 ${(task.elapsedMs / 1000).toFixed(1)} 秒；未执行真实转换或保真检测。`)
          .fontSize(14).fontColor($r('app.color.palette_526077'))
        FidelityReportCard({ report: task.fidelityReport })
      }
      Button('查看任务记录').onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/TaskHistory'); })
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
  @Provide('services') services: ServiceContainer = new ServiceContainer();
  @State model: ConversionStatusVM = new ConversionStatusVM(this.services.tasks);
  build() { ConversionProgressPanel({ model: this.model }) }
}
