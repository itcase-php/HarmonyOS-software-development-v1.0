import { AppLanguage, LanguageManager } from '../common/LanguageManager';

@Component
export struct LanguageToggle {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  build() {
    Button(this.language === 'zh' ? 'EN' : '中').type(ButtonType.Circle).width(40).height(40)
      .fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_007aff'))
      .backgroundColor($r('app.color.palette_edf4ff')).id('language-toggle')
      .accessibilityText(LanguageManager.getString(this.language === 'zh' ? 'language_to_en' : 'language_to_zh', [], this.language))
      .onClick(() => { LanguageManager.toggle(); })
  }
}
