import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';

@Component
export struct TargetFormatSelector {
  @ObjectLink model: FormatSelectionVM;
  build() {
    Column({ space: 12 }) {
      Text('② 选择目标与路线').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
      if (this.model.targetChoices.length > 0) {
        Select(this.model.targetChoices).selected(this.model.targetIndex).value(this.model.targetId.toUpperCase()).width('100%')
          .accessibilityText($r('app.string.a11y_target')).accessibilityDescription($r('app.string.a11y_target'))
          .enabled(this.model.interactive).onSelect((index: number) => { this.model.selectTarget(index); })
      } else { Text('此源格式暂无单文件规划路线，请切换源格式。').fontSize(14).fontColor($r('app.color.palette_c53030')) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Preview
@Component
struct TargetFormatSelectorPreview {
  @State model: FormatSelectionVM = new FormatSelectionVM();
  aboutToAppear(): void { this.model.initializeSelections(); }
  build() { TargetFormatSelector({ model: this.model }) }
}
