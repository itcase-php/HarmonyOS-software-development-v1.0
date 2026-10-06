import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';

@Component
export struct ConversionErrorBanner {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @ObjectLink model: ConversionStatusVM;
  @ObjectLink formats: FormatSelectionVM;
  onRetry: () => void = () => {};
  build() {
    Column({ space: 8 }) {
      if (!this.formats.registryReady) {
        Text(this.formats.registryLoading ? this.tr($r('app.string.registry_loading')) : this.tr($r('app.string.registry_error')))
        Button(this.tr($r('app.string.registry_retry'))).enabled(!this.formats.registryLoading).onClick(() => { this.onRetry(); })
      }
      if (this.model.errorText.length > 0) {
        Text(this.tr(this.model.errorText)).fontSize(14).fontColor($r('app.color.palette_c53030'))
        if (this.model.retryable && !this.model.working && !this.model.inputBusy && !this.model.confirming) {
          Button(this.tr($r('app.string.registry_retry'))).onClick(() => { this.onRetry(); })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
@Preview
@Component
struct ConversionErrorBannerPreview {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @State model: ConversionStatusVM = new ConversionStatusVM();
  @State formats: FormatSelectionVM = new FormatSelectionVM();
  build() { ConversionErrorBanner({ model: this.model, formats: this.formats }) }
}
