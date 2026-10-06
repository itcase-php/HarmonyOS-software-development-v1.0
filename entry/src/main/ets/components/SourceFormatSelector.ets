import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';

@Component
export struct SourceFormatSelector {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @ObjectLink model: FormatSelectionVM;
  build() {
    Column({ space: 12 }) {
      Text(this.tr('source_title')).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
      Select(this.model.sourceChoices).selected(this.model.sourceIndex).value(this.model.sourceId.toUpperCase()).width('100%')
        .accessibilityText(this.tr($r('app.string.a11y_source'))).accessibilityDescription(this.tr($r('app.string.a11y_source')))
        .enabled(this.model.interactive).onSelect((index: number) => { this.model.selectSource(index); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Preview
@Component
struct SourceFormatSelectorPreview {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @State model: FormatSelectionVM = new FormatSelectionVM();
  aboutToAppear(): void { this.model.initializeSelections(); }
  build() { SourceFormatSelector({ model: this.model }) }
}
