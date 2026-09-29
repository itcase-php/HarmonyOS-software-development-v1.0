import { QualityMode } from '../models/NativeProtocol';
import { QualitySelector } from './QualitySelector';

@Component
export struct FidelitySettingsCard {
  @Prop qualityMode: QualityMode = 'balanced';
  @Prop interactive: boolean = true;
  @Prop intentChoices: SelectOption[] = [];
  @Prop tierChoices: SelectOption[] = [];
  @Prop intentIndex: number = 0;
  @Prop tierIndex: number = 0;
  @Prop intentText: string = '';
  @Prop tierText: string = '';
  @Prop routeDescription: string = '';
  @Prop routeNotice: string = '';
  @Prop selectionSummary: string = '';
  @Prop routeAvailable: boolean = true;
  @State expanded: boolean = true;
  onSelectQuality: (mode: QualityMode) => void = () => {};
  onSelectIntent: (index: number) => void = () => {};
  onSelectTier: (index: number) => void = () => {};

  build() {
    Column({ space: 10 }) {
      Button(this.expanded ? $r('app.string.fidelity_collapse') : $r('app.string.fidelity_expand')).fontSize(16)
        .type(ButtonType.Normal).backgroundColor('#EDF4FF').fontColor('#007AFF')
        .accessibilityText($r('app.string.fidelity_settings'))
        .accessibilityDescription(this.expanded ? $r('app.string.a11y_collapse') : $r('app.string.a11y_expand'))
        .onClick(() => { this.expanded = !this.expanded; })
      Text(this.routeDescription).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#172B4D')
      Text(this.selectionSummary).fontSize(13).fontColor('#526077')
      if (this.expanded) {
        Text($r('app.string.quality_mode')).fontSize(14).fontColor('#172B4D')
        QualitySelector({ mode: this.qualityMode, interactive: this.interactive,
          onSelectMode: (mode: QualityMode) => { this.onSelectQuality(mode); } })
        Text($r('app.string.intent_choice')).fontSize(14).fontColor('#172B4D')
        Select(this.intentChoices).selected(this.intentIndex).value(this.intentText).width('100%')
          .enabled(this.interactive && this.intentChoices.length > 0)
          .accessibilityText($r('app.string.intent_choice')).accessibilityDescription($r('app.string.a11y_intent'))
          .onSelect((index: number) => { this.onSelectIntent(index); })
        Text($r('app.string.fidelity_minimum')).fontSize(14).fontColor('#172B4D')
        Select(this.tierChoices).selected(this.tierIndex).value(this.tierText).width('100%')
          .enabled(this.interactive).accessibilityText($r('app.string.fidelity_minimum'))
          .accessibilityDescription($r('app.string.a11y_minimum'))
          .onSelect((index: number) => { this.onSelectTier(index); })
        Text($r('app.string.demo_duration_notice')).fontSize(12).fontColor('#526077')
      }
      Text(this.routeNotice).fontSize(13).fontColor(this.routeAvailable ? '#526077' : '#C53030')
    }.width('100%').padding(12).backgroundColor('#F2F5FA').borderRadius(12).alignItems(HorizontalAlign.Start)
  }
}
