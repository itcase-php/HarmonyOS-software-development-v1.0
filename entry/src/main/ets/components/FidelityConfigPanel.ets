import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';
import { FidelityConfigVM } from '../viewmodel/FidelityConfigVM';
import { FidelitySettingsCard } from './FidelitySettingsCard';
import { QualityMode } from '../models/NativeProtocol';

@Component
export struct FidelityConfigPanel {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

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
          .accessibilityText(this.tr($r('app.string.a11y_route'))).accessibilityDescription(this.model.routeDescription)
          .enabled(this.model.interactive).onSelect((index: number) => { this.formats.selectRoute(index); })
      }
      Row({ space: 8 }) {
        Checkbox({ name: 'approve-demo' }).select(this.formats.approved).enabled(this.model.interactive)
          .accessibilityText(this.tr($r('app.string.a11y_approval'))).accessibilityDescription(this.model.routeNotice)
          .onChange((value: boolean) => { this.formats.approved = value; })
        Text(this.realInput ? this.tr($r('app.string.input_approval')) : this.tr('demo_approval'))
          .fontSize(13).fontColor($r('app.color.palette_526077')).layoutWeight(1)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
@Preview
@Component
struct FidelityConfigPanelPreview {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @State model: FidelityConfigVM = new FidelityConfigVM();
  @State formats: FormatSelectionVM = new FormatSelectionVM(undefined, undefined, this.model);
  aboutToAppear(): void { this.formats.initializeSelections(); }
  build() { FidelityConfigPanel({ model: this.model, formats: this.formats }) }
}
