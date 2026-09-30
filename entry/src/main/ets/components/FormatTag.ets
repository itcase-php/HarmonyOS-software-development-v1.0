@Component
export struct FormatTag {
  @Prop formatId: string = '';

  build() {
    Text(this.formatId.toUpperCase()).fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_007aff'))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor($r('app.color.palette_edf4ff')).borderRadius(6)
  }
}
