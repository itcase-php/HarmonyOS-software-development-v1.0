import { LanguageManager, AppLanguage } from '../common/LanguageManager';
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
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Provide('services') services: ServiceContainer = ServiceContainer.current();
  @State fidelity: FidelityConfigVM = new FidelityConfigVM();
  @State status: ConversionStatusVM = new ConversionStatusVM(this.services.tasks);
  @State formats: FormatSelectionVM = new FormatSelectionVM(this.services.registry, this.services.dependencies.planner, this.fidelity, this.status);
  @State files: FileAuthorizationVM = new FileAuthorizationVM(this.services.files, this.status, this.formats);
  private coordinator: ConverterCoordinator = new ConverterCoordinator(this.formats, this.files, this.status,
    this.services.tasks, this.services.dependencies.planner);
  private languageToken: number = -1;
  aboutToAppear(): void {
    this.coordinator.setUi(new ArkUiConverterUi(this.getUIContext())); this.coordinator.appear();
    this.languageToken = LanguageManager.subscribe(() => { this.coordinator.refreshLanguage(); });
    this.coordinator.refreshLanguage();
  }
  onPageShow(): void { this.coordinator.show(); this.coordinator.refreshLanguage(); }
  onPageHide(): void { this.coordinator.hide(); }
  aboutToDisappear(): void { LanguageManager.unsubscribe(this.languageToken); this.languageToken = -1; this.coordinator.hide(true); }
  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: this.tr('converter_title'), subtitle: this.tr('converter_subtitle') })
        if (this.files.authorizedFiles.length > 0) {
          StatusBadge({ text: this.status.inputText(this.tr($r('app.string.input_real_mode'))), color: $r('app.color.palette_a65c00') })
        } else { StatusBadge({ text: this.tr('demo_badge'), color: $r('app.color.palette_a65c00') }) }
        Text(this.tr('demo_fidelity_notice'))
          .fontSize(14).fontColor($r('app.color.palette_526077'))
        Column({ space: 12 }) {
          SourceFormatSelector({ model: this.formats })
          TargetFormatSelector({ model: this.formats })
          FidelityConfigPanel({ model: this.fidelity, formats: this.formats, realInput: this.files.authorizedFiles.length > 0 })
          Text(this.files.authorizedFiles.length > 0 ? this.tr($r('app.string.input_title')) : this.tr('demo_input_title'))
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
          AuthorizedFilePanel({ model: this.files, status: this.status })
          if (this.files.authorizedFiles.length === 0) {
          TextInput({ text: this.formats.fileName, placeholder: this.tr('demo_filename_placeholder') }).maxLength(180)
            .accessibilityText(this.tr($r('app.string.a11y_filename'))).accessibilityDescription(this.tr($r('app.string.a11y_filename')))
            .enabled(this.formats.interactive).onChange((value: string) => { this.formats.fileName = value; this.status.errorText = ''; })
          Button(this.tr('demo_example')).enabled(this.formats.interactive).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
            .accessibilityText(this.tr('demo_example')).accessibilityDescription(this.tr('demo_example_description'))
            .onClick(() => { this.formats.useExample(); })
          Text(this.tr('demo_input_notice')).fontSize(12).fontColor($r('app.color.palette_526077'))
          }
          ConversionErrorBanner({ model: this.status, formats: this.formats, onRetry: () => { this.coordinator.retry(); } })
          Button(this.files.authorizedFiles.length > 0 ? this.status.inputText(this.tr($r('app.string.input_start_real'))) :
            this.status.working ? this.tr('demo_running') : this.status.confirming ? this.tr('demo_confirming') : this.tr('demo_start_config'))
            .accessibilityText(this.files.authorizedFiles.length > 0 ? this.tr($r('app.string.input_start_real')) : this.tr($r('app.string.a11y_start')))
            .accessibilityDescription(this.fidelity.selectionSummary)
            .enabled(!this.status.working && !this.status.confirming && !this.files.pickingFile && !this.files.fileSubmitting && this.formats.routeId.length > 0).width('100%').backgroundColor($r('app.color.palette_007aff'))
            .onClick(() => { this.coordinator.start(); })
          if (this.status.inlineConfirmationText.length > 0) {
            Text(this.status.inlineConfirmationText).fontSize(14).fontColor($r('app.color.palette_172b4d'))
            Button(this.tr('demo_confirm_start')).onClick(() => { this.coordinator.beginConfirmed(); })
            Button(this.tr('back_edit')).onClick(() => { this.coordinator.cancelConfirmation(); })
          }
          if (this.status.realConfirmationText.length > 0) {
            Text(this.status.realConfirmationText).fontSize(14)
            Button(this.tr($r('app.string.input_start_real'))).onClick(() => { this.coordinator.beginAuthorized(); })
            Button(this.tr($r('app.string.input_back_edit'))).onClick(() => { this.coordinator.cancelAuthorizedConfirmation(); })
          }
        }.width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16).alignItems(HorizontalAlign.Start)
        ConversionProgressPanel({ model: this.status })
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
