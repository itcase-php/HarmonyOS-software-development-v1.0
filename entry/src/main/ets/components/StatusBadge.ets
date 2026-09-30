@Component
export struct StatusBadge {
  @Require @Prop text: string = '';
  @Prop color: ResourceColor = $r('app.color.palette_526077');

  build() {
    Text(this.text).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.color)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor($r('app.color.palette_f2f5fa')).borderRadius(8)
  }
}
