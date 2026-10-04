import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { FormatSelectionVM } from '../viewmodel/FormatSelectionVM';

@Component
export struct TargetFormatSelector {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @ObjectLink model: FormatSelectionVM;
  build() {
    Column({ space: 12 }) {
      Text(this.tr('target_title')).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
      if (this.model.targetChoices.length > 0) {
        Select(this.model.targetChoices).selected(this.model.targetIndex).value(this.model.targetId.toUpperCase()).width('100%')
          .accessibilityText(this.tr($r('app.string.a11y_target'))).accessibilityDescription(this.tr($r('app.string.a11y_target')))
          .enabled(this.model.interactive).onSelect((index: number) => { this.model.selectTarget(index); })
      } else { Text(this.tr('target_missing')).fontSize(14).fontColor($r('app.color.palette_c53030')) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Preview
@Component
struct TargetFormatSelectorPreview {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @State model: FormatSelectionVM = new FormatSelectionVM();
  aboutToAppear(): void { this.model.initializeSelections(); }
  build() { TargetFormatSelector({ model: this.model }) }
}
