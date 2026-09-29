@Component
export struct StatusBadge {
  @Prop text: string = '';
  @Prop color: string = '#526077';

  build() {
    Text(this.text).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.color)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor('#F2F5FA').borderRadius(8)
  }
}
