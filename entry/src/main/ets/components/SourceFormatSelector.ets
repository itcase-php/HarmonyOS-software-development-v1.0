import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';

@Component
export struct SourceFormatSelector {
  @ObjectLink model: FormatSelectionVM;
  build() {
    Column({ space: 12 }) {
      Text('① 选择源格式').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
      Select(this.model.sourceChoices).selected(this.model.sourceIndex).value(this.model.sourceId.toUpperCase()).width('100%')
        .accessibilityText($r('app.string.a11y_source')).accessibilityDescription($r('app.string.a11y_source'))
        .enabled(this.model.interactive).onSelect((index: number) => { this.model.selectSource(index); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Preview
@Component
struct SourceFormatSelectorPreview {
  @State model: FormatSelectionVM = new FormatSelectionVM();
  aboutToAppear(): void { this.model.initializeSelections(); }
  build() { SourceFormatSelector({ model: this.model }) }
}
