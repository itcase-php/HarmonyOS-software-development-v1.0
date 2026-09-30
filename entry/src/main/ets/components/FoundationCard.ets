@Component
export struct FoundationCard {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.label).fontSize(14).fontColor($r('app.color.palette_526077'))
      Text(this.value).fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor($r('app.color.palette_ffffff'))
    .borderRadius(12)
  }
}
