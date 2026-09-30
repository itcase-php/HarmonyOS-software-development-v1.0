import { ServiceContainer } from '../services/ServiceContainer';
import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';
import { FidelityConfigVM } from '../viewmodel/FidelityConfigVM';
import { FileAuthorizationVM } from '../viewmodel/FileAuthorizationVM';
import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { ConverterCoordinator } from '../viewmodel/ConverterCoordinator';
import { ArkUiConverterUi } from '../common/ArkUiConverterUi';
import { PageHeader } from '../components/PageHeader';
import { StatusBadge } from '../components/StatusBadge';
import { SourceFormatSelector } from '../components/SourceFormatSelector';
import { TargetFormatSelector } from '../components/TargetFormatSelector';
import { FidelityConfigPanel } from '../components/FidelityConfigPanel';
import { AuthorizedFilePanel } from '../components/AuthorizedFilePanel';
import { ConversionProgressPanel } from '../components/ConversionProgressPanel';
import { ConversionErrorBanner } from '../components/ConversionErrorBanner';

@Entry
@Preview
@Component
struct ConverterPage {
  @Provide('services') services: ServiceContainer = ServiceContainer.current();
  @State fidelity: FidelityConfigVM = new FidelityConfigVM();
  @State status: ConversionStatusVM = new ConversionStatusVM(this.services.tasks);
  @State formats: FormatSelectionVM = new FormatSelectionVM(this.services.registry, this.services.dependencies.planner, this.fidelity, this.status);
  @State files: FileAuthorizationVM = new FileAuthorizationVM(this.services.files, this.status, this.formats);
  private coordinator: ConverterCoordinator = new ConverterCoordinator(this.formats, this.files, this.status,
    this.services.tasks, this.services.dependencies.planner);
  aboutToAppear(): void { this.coordinator.setUi(new ArkUiConverterUi(this.getUIContext())); this.coordinator.appear(); }
  onPageShow(): void { this.coordinator.show(); }
  onPageHide(): void { this.coordinator.hide(); }
  aboutToDisappear(): void { this.coordinator.hide(true); }
  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: '转换执行器', subtitle: '选择格式、设置保真策略、确认后体验任务流程' })
        if (this.files.authorizedFiles.length > 0) {
          StatusBadge({ text: this.status.inputText($r('app.string.input_real_mode')), color: $r('app.color.palette_a65c00') })
        } else { StatusBadge({ text: '演示模式 · 不生成文件', color: $r('app.color.palette_a65c00') }) }
        Text('真实转换引擎尚未接入。保真设置与报告均用于交互演示，不是文件质量的测量结果。')
          .fontSize(14).fontColor($r('app.color.palette_526077'))
        Column({ space: 12 }) {
          SourceFormatSelector({ model: this.formats })
          TargetFormatSelector({ model: this.formats })
          FidelityConfigPanel({ model: this.fidelity, formats: this.formats, realInput: this.files.authorizedFiles.length > 0 })
          Text(this.files.authorizedFiles.length > 0 ? $r('app.string.input_title') : '③ 模拟选择文件')
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
          AuthorizedFilePanel({ model: this.files, status: this.status })
          if (this.files.authorizedFiles.length === 0) {
          TextInput({ text: this.formats.fileName, placeholder: '填写文件名及扩展名' }).maxLength(180)
            .accessibilityText($r('app.string.a11y_filename')).accessibilityDescription($r('app.string.a11y_filename'))
            .enabled(this.formats.interactive).onChange((value: string) => { this.formats.fileName = value; this.status.errorText = ''; })
          Button('填入示例文件名').enabled(this.formats.interactive).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
            .accessibilityText('填入示例文件名').accessibilityDescription('只设置演示名称，不读取文件')
            .onClick(() => { this.formats.useExample(); })
          Text('只填写演示名称，不读取或上传设备文件。').fontSize(12).fontColor($r('app.color.palette_526077'))
          }
          ConversionErrorBanner({ model: this.status, formats: this.formats, onRetry: () => { this.coordinator.retry(); } })
          Button(this.files.authorizedFiles.length > 0 ? this.status.inputText($r('app.string.input_start_real')) :
            this.status.working ? '演示任务进行中' : this.status.confirming ? '等待配置确认' : '④ 确认配置并开始演示')
            .accessibilityText(this.files.authorizedFiles.length > 0 ? $r('app.string.input_start_real') : $r('app.string.a11y_start'))
            .accessibilityDescription(this.fidelity.selectionSummary)
            .enabled(!this.status.working && !this.status.confirming && !this.files.pickingFile && !this.files.fileSubmitting && this.formats.routeId.length > 0).width('100%').backgroundColor($r('app.color.palette_007aff'))
            .onClick(() => { this.coordinator.start(); })
          if (this.status.inlineConfirmationText.length > 0) {
            Text(this.status.inlineConfirmationText).fontSize(14).fontColor($r('app.color.palette_172b4d'))
            Button('确认开始演示').onClick(() => { this.coordinator.beginConfirmed(); })
            Button('返回修改').onClick(() => { this.coordinator.cancelConfirmation(); })
          }
          if (this.status.realConfirmationText.length > 0) {
            Text(this.status.realConfirmationText).fontSize(14)
            Button($r('app.string.input_start_real')).onClick(() => { this.coordinator.beginAuthorized(); })
            Button($r('app.string.input_back_edit')).onClick(() => { this.coordinator.cancelAuthorizedConfirmation(); })
          }
        }.width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).alignItems(HorizontalAlign.Start)
        ConversionProgressPanel({ model: this.status })
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
