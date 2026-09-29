import { UiFeedback } from '../common/UiFeedback';

@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: 8 }) {
      Button('‹ 返回').fontSize(14).type(ButtonType.Normal).backgroundColor('#E5ECF5').fontColor('#172B4D')
        .onClick(() => { UiFeedback.back(this.getUIContext()); })
      Text(this.title).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#172B4D')
      Text(this.subtitle).fontSize(14).fontColor('#526077')
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
