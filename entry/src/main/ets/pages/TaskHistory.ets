import { DemoTask, taskStatusLabel, taskStatusColor, isActiveTask } from '../models/InteractionModels';
import { TaskStore } from '../viewmodel/TaskStore';
import { UiFeedback } from '../common/UiFeedback';
import { PageHeader } from '../components/PageHeader';
import { StatusBadge } from '../components/StatusBadge';
import { FormatTag } from '../components/FormatTag';
import { FidelityReportCard } from '../components/FidelityReportCard';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';

@Entry
@Preview
@Component
struct TaskHistory {
  @State tasks: DemoTask[] = [];
  private store: TaskStore = TaskStore.shared();
  private token: number = -1;

  aboutToAppear(): void {
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
    UiFeedback.toast(this.getUIContext(), `已清除 ${count} 条结束记录，活动任务保留`);
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: '任务记录', subtitle: '本次应用会话中的任务记录；退出应用后不会保留' })
        Row({ space: 12 }) {
          Text(`${this.tasks.length} 条记录`).fontSize(16).fontColor('#526077').layoutWeight(1)
          Button('清除已结束记录').fontSize(13)
            .accessibilityText('清除已结束记录').accessibilityDescription('活动任务会保留')
            .enabled(this.tasks.some((task: DemoTask) => !isActiveTask(task.status)))
            .onClick(() => { this.clear(); })
        }.width('100%')
        if (this.tasks.length === 0) {
          Column({ space: 12 }) {
            Text('≡').fontSize(44).fontColor('#526077')
            Text('暂无任务记录').fontSize(20).fontWeight(FontWeight.Medium).fontColor('#172B4D')
            Text('先选择格式并开始一次交互演示').fontSize(14).fontColor('#526077')
            Button('开始演示').onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage'); })
          }.width('100%').padding(32).backgroundColor('#FFFFFF').borderRadius(16)
        }
        ForEach(this.tasks, (task: DemoTask) => {
          Column({ space: 10 }) {
            Text(task.fileName).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#172B4D').maxLines(2)
            Row({ space: 8 }) {
              FormatTag({ formatId: task.sourceFormat })
              Text('→').fontColor('#526077')
              FormatTag({ formatId: task.targetFormat })
              Blank()
              StatusBadge({ text: taskStatusLabel(task.status, task.mode), color: taskStatusColor(task.status) })
            }.width('100%')
            Text(new Date(task.createdAtMs).toLocaleString()).fontSize(12).fontColor('#526077')
            Text(`${task.stage} · ${(task.elapsedMs / 1000).toFixed(1)} 秒`).fontSize(13).fontColor('#526077')
            Text(`${FidelityPolicy.qualityLabel(task.qualityMode)} · ${FidelityPolicy.intentLabel(task.requestedIntent)} · 最低${FidelityPolicy.tierLabel(task.requestedTier)}`)
              .fontSize(13).fontColor('#526077')
            if (isActiveTask(task.status)) {
              Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%').color('#007AFF')
              Row({ space: 10 }) {
                if (task.status === 'running' && task.mode === 'demo') {
                  Button('暂停').fontSize(13).accessibilityText('暂停任务').accessibilityDescription(task.fileName)
                    .onClick(() => { this.store.pause(task.id); })
                }
                if (task.status === 'paused') {
                  Button('继续').fontSize(13).accessibilityText('继续任务').accessibilityDescription(task.fileName)
                    .onClick(() => { this.store.resume(task.id); })
                }
                Button('取消').fontSize(13).backgroundColor('#E5ECF5').fontColor('#172B4D')
                  .accessibilityText('取消任务').accessibilityDescription(task.fileName)
                  .onClick(() => { this.store.cancel(task.id); UiFeedback.toast(this.getUIContext(), '已请求取消任务'); })
              }
            }
            if (task.resultLabel.length > 0) {
              Text(task.resultLabel).fontSize(14).fontColor('#167644')
            }
            if (task.status === 'completed' && task.fidelityReport) {
              FidelityReportCard({ report: task.fidelityReport, mode: task.mode })
            }
            if (task.mode === 'native' && task.status === 'completed' && !task.fidelityReport) {
              Text($r('app.string.report_missing')).fontSize(13).fontColor('#526077')
            }
            if (task.error.length > 0) { Text(task.error).fontSize(13).fontColor('#C53030') }
            Text(task.mode === 'demo' ? '演示记录 · 未生成真实文件' :
              task.status === 'completed' ? 'Native 任务记录 · 内部输出尚未导出' : 'Native 任务记录 · 未生成可用输出')
              .fontSize(12).fontColor('#526077')
          }.width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(16).alignItems(HorizontalAlign.Start)
        }, (task: DemoTask) => `${task.id}-${task.status}-${task.progress}-${task.elapsedMs}`)
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor('#F2F5FA')
  }
}
