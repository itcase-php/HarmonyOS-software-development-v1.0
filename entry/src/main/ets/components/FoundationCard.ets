@Component
export struct FoundationCard {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.label).fontSize(14).fontColor('#526077')
      Text(this.value).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#172B4D')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }
}
