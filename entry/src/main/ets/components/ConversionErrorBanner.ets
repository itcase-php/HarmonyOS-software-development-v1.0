import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';

@Component
export struct ConversionErrorBanner {
  @ObjectLink model: ConversionStatusVM;
  @ObjectLink formats: FormatSelectionVM;
  onRetry: () => void = () => {};
  build() {
    Column({ space: 8 }) {
      if (!this.formats.registryReady) {
        Text(this.formats.registryLoading ? $r('app.string.registry_loading') : $r('app.string.registry_error'))
        Button($r('app.string.registry_retry')).enabled(!this.formats.registryLoading).onClick(() => { this.onRetry(); })
      }
      if (this.model.errorText.length > 0) {
        Text(this.model.errorText).fontSize(14).fontColor($r('app.color.palette_c53030'))
        if (this.model.retryable && !this.model.working && !this.model.inputBusy && !this.model.confirming) {
          Button($r('app.string.registry_retry')).onClick(() => { this.onRetry(); })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
@Preview
@Component
struct ConversionErrorBannerPreview {
  @State model: ConversionStatusVM = new ConversionStatusVM();
  @State formats: FormatSelectionVM = new FormatSelectionVM();
  build() { ConversionErrorBanner({ model: this.model, formats: this.formats }) }
}
