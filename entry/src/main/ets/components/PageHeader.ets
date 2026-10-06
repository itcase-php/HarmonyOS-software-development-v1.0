import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { UiFeedback } from '../common/UiFeedback';

@Component
export struct PageHeader {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  // Callers resolve these labels in their own reactive language binding.
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: 8 }) {
      Button(this.tr($r('app.string.navigation_back'))).fontSize(14).type(ButtonType.Normal).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
        .onClick(() => { UiFeedback.back(this.getUIContext()); })
      Text(this.title).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
      Text(this.subtitle).fontSize(14).fontColor($r('app.color.palette_526077'))
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
