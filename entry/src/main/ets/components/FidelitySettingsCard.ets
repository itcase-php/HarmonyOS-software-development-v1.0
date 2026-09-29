import { QualityMode } from '../models/NativeProtocol';
import { FidelitySettingsVM } from '../models/InteractionModels';
import { QualitySelector } from './QualitySelector';

@Component
export struct FidelitySettingsCard {
  @Prop vm: FidelitySettingsVM | null = null;
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
      Text(this.vm?.routeDescription ?? '').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#172B4D')
      Text(this.vm?.selectionSummary ?? '').fontSize(13).fontColor('#526077')
      if (this.expanded) {
        Text($r('app.string.quality_mode')).fontSize(14).fontColor('#172B4D')
        QualitySelector({ mode: this.vm?.qualityMode ?? 'balanced', interactive: this.vm?.interactive ?? false,
          onSelectMode: (mode: QualityMode) => { this.onSelectQuality(mode); } })
        Text($r('app.string.intent_choice')).fontSize(14).fontColor('#172B4D')
        Select(this.vm?.intentChoices ?? []).selected(this.vm?.intentIndex ?? 0).value(this.vm?.intentText ?? '').width('100%')
          .enabled((this.vm?.interactive ?? false) && (this.vm?.intentChoices.length ?? 0) > 0)
          .accessibilityText($r('app.string.intent_choice')).accessibilityDescription($r('app.string.a11y_intent'))
          .onSelect((index: number) => { this.onSelectIntent(index); })
        Text($r('app.string.fidelity_minimum')).fontSize(14).fontColor('#172B4D')
        Select(this.vm?.tierChoices ?? []).selected(this.vm?.tierIndex ?? 1).value(this.vm?.tierText ?? '').width('100%')
          .enabled(this.vm?.interactive ?? false).accessibilityText($r('app.string.fidelity_minimum'))
          .accessibilityDescription($r('app.string.a11y_minimum'))
          .onSelect((index: number) => { this.onSelectTier(index); })
        Text($r('app.string.demo_duration_notice')).fontSize(12).fontColor('#526077')
      }
      Text(this.vm?.routeNotice ?? '').fontSize(13).fontColor((this.vm?.routeAvailable ?? false) ? '#526077' : '#C53030')
    }.width('100%').padding(12).backgroundColor('#F2F5FA').borderRadius(12).alignItems(HorizontalAlign.Start)
  }
}
