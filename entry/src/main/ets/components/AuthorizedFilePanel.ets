import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { FileAuthorizationVM } from '../viewmodel/FileAuthorizationVM';
import { ConversionStatusVM } from '../viewmodel/ConversionStatusVM';
import { AuthorizedFile } from '../models/SessionModels';
import { FormatTag } from './FormatTag';

@Component
export struct AuthorizedFilePanel {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @ObjectLink model: FileAuthorizationVM;
  @ObjectLink status: ConversionStatusVM;
  build() {
    Column({ space: 10 }) {
      if (!this.model.filePickerAvailable) {
        Text(this.tr($r('app.string.preview_file_picker_hint'))).fontSize(13).fontColor($r('app.color.palette_526077'))
      } else if (this.model.authorizedFiles.length === 0) {
        Button(this.tr($r('app.string.select_source_file'))).enabled(!this.model.pickingFile && !this.model.fileSubmitting && !this.status.working && !this.status.confirming)
          .accessibilityText(this.tr($r('app.string.select_source_file'))).onClick(() => { this.model.pickSourceFiles(); })
      }
      if (this.model.pickingFile) { Text(this.tr($r('app.string.input_importing'))).fontSize(13).fontColor($r('app.color.palette_526077')) }
      if (this.model.fileSubmitting) { Text(this.tr($r('app.string.input_submitting'))).fontSize(13).fontColor($r('app.color.palette_526077')) }
      if (this.model.authorizedFiles.length > 0) {
      List({ space: 10 }) {
      LazyForEach(this.model.dataSource, (file: AuthorizedFile) => {
        ListItem() {
        Column({ space: 6 }) {
          Text(file.originalName).fontSize(16).fontWeight(FontWeight.Medium)
          Row({ space: 8 }) { Text(this.model.fileSizeText(file.byteSize)).fontSize(13); FormatTag({ formatId: file.detectedFormatId }) }
          Text(this.tr($r('app.string.input_detection_hint'))).fontSize(12).fontColor($r('app.color.palette_526077'))
          if (file.warnings && file.warnings.length > 0) { Text(this.tr($r('app.string.input_mime_warning'))).fontSize(12).fontColor($r('app.color.palette_a65c00')) }
          Button(this.tr($r('app.string.input_remove'))).enabled(!this.model.pickingFile && !this.model.fileSubmitting && !this.status.working && !this.status.confirming)
            .accessibilityText(this.tr($r('app.string.input_remove'))).onClick(() => { this.model.removeSourceFile(file.fileId); })
        }.width('100%').padding(12).backgroundColor($r('app.color.palette_f2f5fa')).borderRadius(10)
        }
      }, (file: AuthorizedFile) => `${file.fileId}-${this.language}`)
      }.width('100%').height(Math.min(this.model.authorizedFiles.length * 180, 420))
      }
      if (this.model.authorizedFiles.length > 0) { Text(this.tr($r('app.string.input_native_boundary'))).fontSize(12).fontColor($r('app.color.palette_526077')) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

}
@Preview
@Component
struct AuthorizedFilePanelPreview {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @State status: ConversionStatusVM = new ConversionStatusVM();
  @State model: FileAuthorizationVM = new FileAuthorizationVM(undefined, this.status);
  build() { AuthorizedFilePanel({ model: this.model, status: this.status }) }
}
