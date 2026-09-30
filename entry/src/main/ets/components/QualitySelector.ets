import { QualityMode } from '../models/NativeProtocol';
interface QualityOption { value: QualityMode; label: Resource; }

@Component
export struct QualitySelector {
  @Prop mode: QualityMode = 'balanced';
  @Prop interactive: boolean = true;
  onSelectMode: (mode: QualityMode) => void = () => {};
  private choices: QualityOption[] = [
    { value: 'fast', label: $r('app.string.quality_fast') }, { value: 'balanced', label: $r('app.string.quality_balanced') },
    { value: 'high_fidelity', label: $r('app.string.quality_high') }
  ];

  build() {
    Row({ space: 6 }) {
      ForEach(this.choices, (choice: QualityOption) => {
        Button(choice.label).layoutWeight(1).fontSize(14).type(ButtonType.Normal).borderRadius(10)
          .labelStyle({ maxLines: 1, minFontSize: 11, maxFontSize: 14,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
          .backgroundColor(this.mode === choice.value ? $r('app.color.palette_007aff') : $r('app.color.palette_e5ecf5'))
          .fontColor(this.mode === choice.value ? $r('app.color.palette_ffffff') : $r('app.color.palette_172b4d'))
          .enabled(this.interactive).onClick(() => { this.onSelectMode(choice.value); })
          .accessibilityText(choice.label)
          .accessibilityDescription(this.mode === choice.value ? $r('app.string.a11y_quality_selected') : $r('app.string.a11y_quality'))
      }, (choice: QualityOption) => choice.value)
    }.width('100%')
  }
}
