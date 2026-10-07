import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { OfficePackageWriter, OfficePage } from './OfficePackageWriter';

export class PdfRebuildProbe {
  static async inspect(root: string): Promise<void> {
    const document = new pdfService.PdfDocument();
    try {
      if (document.loadDocument(root + '/editable-input.pdf') !== pdfService.ParseResult.PARSE_SUCCESS) {
        throw new Error('PDF_FIXTURE_LOAD');
      }
      for (let index: number = 0; index < document.getPageCount(); index++) {
        const page = document.getPage(index);
        try {
          hilog.info(0, 'OfficeStageProbe', 'PDF_BOX=%{public}s', JSON.stringify(page.getBox(pdfService.BoxType.BOX_MEDIA)));
          for (const object of page.getGraphicsObjects()) {
            hilog.info(0, 'OfficeStageProbe', 'PDF_OBJECT=%{public}s', JSON.stringify(object));
          }
        } finally { page.release(); }
      }
    } finally { document.releaseDocument(); }
    const pages: OfficePage[] = [{ width: 612, height: 792, texts: [{ text: 'Editable package 12345',
      x: 40, y: 50, width: 400, height: 30, font: 'DejaVu Sans', size: 20, color: '000000' }], images: [] }];
    for (const extension of ['docx', 'pptx']) {
      const bytes = extension === 'docx' ? OfficePackageWriter.docx(pages) : OfficePackageWriter.pptx(pages);
      const file = await fileIo.open(root + '/rebuilt.' + extension,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        let written: number = 0;
        while (written < bytes.length) {
          const count = await fileIo.write(file.fd, bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + bytes.byteLength));
          if (count <= 0) { throw new Error('OOXML_PROBE_WRITE'); }
          written += count;
        }
      } finally { await fileIo.close(file); }
    }
    hilog.info(0, 'OfficeStageProbe', 'OOXML_DEVICE_WRITER_PASSED');
  }
}
