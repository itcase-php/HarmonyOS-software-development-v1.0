@Component
export struct ActionCard {
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop symbol: string = '';
  @Prop busy: boolean = false;
  onAction: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Text(this.symbol).fontSize(24).fontColor('#007AFF')
        Text(this.busy ? '检测中…' : this.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#172B4D')
        Text(this.description).fontSize(13).fontColor('#526077').maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
    }
    .height(148).width('100%').backgroundColor('#FFFFFF').borderRadius(16)
    .enabled(!this.busy).onClick(() => { this.onAction(); })
    .accessibilityText(this.title)
  }
}
