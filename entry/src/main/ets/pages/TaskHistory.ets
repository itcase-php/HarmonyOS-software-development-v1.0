import { ServiceContainer } from '../services/ServiceContainer';
import { DemoTask, taskStatusLabel, taskStatusColor, isActiveTask } from '../models/InteractionModels';
import { TaskStore } from '../viewmodel/TaskStore';
import { UiFeedback } from '../common/UiFeedback';
import { PageHeader } from '../components/PageHeader';
import { StatusBadge } from '../components/StatusBadge';
import { FormatTag } from '../components/FormatTag';
import { FidelityReportCard } from '../components/FidelityReportCard';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';
import { common } from '@kit.AbilityKit';
import { ArtifactDelivery } from '../services/ArtifactDelivery';

@Entry
@Preview
@Component
struct TaskHistory {
  private services: ServiceContainer = ServiceContainer.current();
  @State tasks: DemoTask[] = [];
  private store: TaskStore = this.services.tasks;
  private delivery: ArtifactDelivery = new ArtifactDelivery(this.store, this.services.native);
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

  private async savePdf(id: string): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved: boolean = await this.delivery.save(id, context);
      UiFeedback.toast(this.getUIContext(), saved ? 'PDF 已保存' : '已取消保存');
    } catch (error) { UiFeedback.toast(this.getUIContext(), 'PDF 保存失败，请重试'); }
  }

  private async sharePdf(id: string): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.delivery.share(id, context);
    } catch (error) { UiFeedback.toast(this.getUIContext(), '分享面板未能打开，请重试'); }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: '任务记录', subtitle: '本次应用会话中的任务记录；退出应用后不会保留' })
        Row({ space: 12 }) {
          Text(`${this.tasks.length} 条记录`).fontSize(16).fontColor($r('app.color.palette_526077')).layoutWeight(1)
          Button('清除已结束记录').fontSize(13)
            .accessibilityText('清除已结束记录').accessibilityDescription('活动任务会保留')
            .enabled(this.tasks.some((task: DemoTask) => !isActiveTask(task.status)))
            .onClick(() => { this.clear(); })
        }.width('100%')
        if (this.tasks.length === 0) {
          Column({ space: 12 }) {
            Text('≡').fontSize(44).fontColor($r('app.color.palette_526077'))
            Text('暂无任务记录').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
            Text('先选择格式并开始一次交互演示').fontSize(14).fontColor($r('app.color.palette_526077'))
            Button('开始演示').onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage'); })
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
              StatusBadge({ text: taskStatusLabel(task.status, task.mode), color: taskStatusColor(task.status) })
            }.width('100%')
            Text(new Date(task.createdAtMs).toLocaleString()).fontSize(12).fontColor($r('app.color.palette_526077'))
            Text(`${task.stage} · ${(task.elapsedMs / 1000).toFixed(1)} 秒`).fontSize(13).fontColor($r('app.color.palette_526077'))
            Text(`${FidelityPolicy.qualityLabel(task.qualityMode)} · ${FidelityPolicy.intentLabel(task.requestedIntent)} · 最低${FidelityPolicy.tierLabel(task.requestedTier)}`)
              .fontSize(13).fontColor($r('app.color.palette_526077'))
            if (isActiveTask(task.status)) {
              Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).width('100%').color($r('app.color.palette_007aff'))
              Row({ space: 10 }) {
                if (task.status === 'running' && task.mode === 'demo') {
                  Button('暂停').fontSize(13).accessibilityText('暂停任务').accessibilityDescription(task.fileName)
                    .onClick(() => { this.store.pause(task.id); })
                }
                if (task.status === 'paused') {
                  Button('继续').fontSize(13).accessibilityText('继续任务').accessibilityDescription(task.fileName)
                    .onClick(() => { this.store.resume(task.id); })
                }
                Button('取消').fontSize(13).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
                  .accessibilityText('取消任务').accessibilityDescription(task.fileName)
                  .onClick(() => { this.store.cancel(task.id); UiFeedback.toast(this.getUIContext(), '已请求取消任务'); })
              }
            }
            if (task.resultLabel.length > 0) {
              Text(task.resultLabel).fontSize(14).fontColor($r('app.color.palette_167644'))
            }
            if (task.status === 'completed' && task.fidelityReport) {
              FidelityReportCard({ report: task.fidelityReport, mode: task.mode })
            }
            if (task.mode === 'native' && task.status === 'completed' && task.targetFormat === 'pdf' &&
              this.store.hasDeliverable(task.id)) {
              Row({ space: 10 }) {
                Button('保存 PDF').fontSize(13).accessibilityText('保存 PDF 到所选位置')
                  .onClick(() => { this.savePdf(task.id); })
                Button('分享 PDF').fontSize(13).accessibilityText('分享 PDF').id(`share-${task.id}`)
                  .onClick(() => { this.sharePdf(task.id); })
              }
            }
            if (task.mode === 'native' && task.status === 'completed' && !task.fidelityReport) {
              Text($r('app.string.report_missing')).fontSize(13).fontColor($r('app.color.palette_526077'))
            }
            if (task.error.length > 0) { Text(task.error).fontSize(13).fontColor($r('app.color.palette_c53030')) }
            Text(task.mode === 'demo' ? '演示记录 · 未生成真实文件' :
              task.status === 'completed' ?
                this.store.exportSnapshot(task.id).some((record) => record.state === 'exported') ?
                  'Native 任务记录 · PDF 已保存' : 'Native 任务记录 · 内部输出可保存或分享' :
                'Native 任务记录 · 未生成可用输出')
              .fontSize(12).fontColor($r('app.color.palette_526077'))
          }.width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).alignItems(HorizontalAlign.Start)
        }, (task: DemoTask) => `${task.id}-${task.status}-${task.progress}-${task.elapsedMs}-${task.resultLabel}`)
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
