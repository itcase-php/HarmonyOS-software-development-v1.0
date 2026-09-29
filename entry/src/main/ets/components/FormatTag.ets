@Component
export struct FormatTag {
  @Prop formatId: string = '';

  build() {
    Text(this.formatId.toUpperCase()).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#007AFF')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EDF4FF').borderRadius(6)
  }
}
