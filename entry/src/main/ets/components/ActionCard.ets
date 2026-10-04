import { LanguageManager, AppLanguage } from '../common/LanguageManager';
@Component
export struct ActionCard {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Prop title: string = '';
  @Prop description: string = '';
  @Prop symbol: string = '';
  @Prop busy: boolean = false;
  onAction: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Text(this.symbol).fontSize(24).fontColor($r('app.color.palette_007aff'))
        Text(this.busy ? this.tr('detecting') : this.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
        Text(this.description).fontSize(13).fontColor($r('app.color.palette_526077')).maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
    }
    .height(148).width('100%').backgroundColor($r('app.color.palette_ffffff')).borderRadius(16)
    .enabled(!this.busy).onClick(() => { this.onAction(); })
    .accessibilityText(this.title)
  }
}
