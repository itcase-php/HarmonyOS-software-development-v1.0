import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';
import { FidelityConfigVM } from '../viewmodel/FidelityConfigVM';
import { FidelitySettingsCard } from './FidelitySettingsCard';
import { QualityMode } from '../models/NativeProtocol';

@Component
export struct FidelityConfigPanel {
  @ObjectLink model: FidelityConfigVM;
  @ObjectLink formats: FormatSelectionVM;
  @Prop realInput: boolean = false;
  build() {
    Column({ space: 12 }) {
      FidelitySettingsCard({ vm: this.model,
        onSelectQuality: (mode: QualityMode) => { this.formats.selectQuality(mode); },
        onSelectIntent: (index: number) => { this.formats.selectIntent(index); },
        onSelectTier: (index: number) => { this.formats.selectTier(index); } })
      if (this.formats.routeChoices.length > 0) {
        Select(this.formats.routeChoices).selected(this.formats.routeIndex).value(this.formats.routeId).width('100%')
          .accessibilityText($r('app.string.a11y_route')).accessibilityDescription(this.model.routeDescription)
          .enabled(this.model.interactive).onSelect((index: number) => { this.formats.selectRoute(index); })
      }
      Row({ space: 8 }) {
        Checkbox({ name: 'approve-demo' }).select(this.formats.approved).enabled(this.model.interactive)
          .accessibilityText($r('app.string.a11y_approval')).accessibilityDescription(this.model.routeNotice)
          .onChange((value: boolean) => { this.formats.approved = value; })
        Text(this.realInput ? $r('app.string.input_approval') : '同意演示所选路线配置的兼容降级')
          .fontSize(13).fontColor($r('app.color.palette_526077')).layoutWeight(1)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
@Preview
@Component
struct FidelityConfigPanelPreview {
  @State model: FidelityConfigVM = new FidelityConfigVM();
  @State formats: FormatSelectionVM = new FormatSelectionVM(undefined, undefined, this.model);
  aboutToAppear(): void { this.formats.initializeSelections(); }
  build() { FidelityConfigPanel({ model: this.model, formats: this.formats }) }
}
