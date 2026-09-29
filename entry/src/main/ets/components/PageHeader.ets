import { UiFeedback } from '../common/UiFeedback';

@Component
export struct PageHeader {
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';

  build() {
    Column({ space: 8 }) {
      Button($r('app.string.navigation_back')).fontSize(14).type(ButtonType.Normal).backgroundColor('#E5ECF5').fontColor('#172B4D')
        .onClick(() => { UiFeedback.back(this.getUIContext()); })
      Text(this.title).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#172B4D')
      Text(this.subtitle).fontSize(14).fontColor('#526077')
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
