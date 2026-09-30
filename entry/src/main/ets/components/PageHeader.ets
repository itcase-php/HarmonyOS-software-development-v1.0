import { UiFeedback } from '../common/UiFeedback';

@Component
export struct PageHeader {
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';

  build() {
    Column({ space: 8 }) {
      Button($r('app.string.navigation_back')).fontSize(14).type(ButtonType.Normal).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
        .onClick(() => { UiFeedback.back(this.getUIContext()); })
      Text(this.title).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
      Text(this.subtitle).fontSize(14).fontColor($r('app.color.palette_526077'))
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
