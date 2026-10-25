import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { PdfOfficeConverter } from './PdfOfficeConverter';

export class PdfRebuildProbe {
  static async inspect(root: string): Promise<void> {
    const document = new pdfService.PdfDocument();
    try {
      if (document.loadDocument(root + '/editable-input.pdf') !== pdfService.ParseResult.PARSE_SUCCESS) {
        throw new Error('PDF_FIXTURE_LOAD');
      }
      for (let index: number = 0; index < document.getPageCount(); index++) {
        const page = document.getPage(index);
        let objects: pdfService.GraphicsObject[] = [];
        try {
          hilog.info(0, 'OfficeStageProbe', 'PDF_BOX=%{public}s', JSON.stringify(page.getBox(pdfService.BoxType.BOX_MEDIA)));
          objects = page.getGraphicsObjects();
          for (const object of objects) {
            hilog.info(0, 'OfficeStageProbe', 'PDF_OBJECT=%{public}s', JSON.stringify(object));
          }
        } finally {
          try {
            await Promise.allSettled(objects
              .filter((object: pdfService.GraphicsObject) => object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE)
              .map((object: pdfService.GraphicsObject) => (object as pdfService.ImageObject).pixelMap.release()));
          } finally { page.release(); }
        }
      }
    } finally { document.releaseDocument(); }
    const deadline: number = Date.now() + 30000;
    for (const extension of ['docx', 'pptx']) {
      const result = await PdfOfficeConverter.convert(root + '/editable-input.pdf', extension,
        [{ pdfName: 'DejaVuSans', officeName: 'DejaVu Sans' }],
        // Only this locally generated, known unsigned fixture is admitted by the probe.
        { fileId: 'stage-fixture', actualFormatId: 'pdf', protection: 'none', needsDeepCheck: false }, () => {
          if (Date.now() >= deadline) { throw new Error('PDF_REBUILD_TIMEOUT'); }
        });
      const bytes = result.bytes;
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
      hilog.info(0, 'OfficeStageProbe', 'PDF_REBUILD_%{public}s pages=%{public}d text=%{public}d images=%{public}d bytes=%{public}d',
        extension, result.sourcePages, result.textObjects, result.imageObjects, bytes.length);
    }
    hilog.info(0, 'OfficeStageProbe', 'PDF_REBUILD_COMPLETED_REQUIRES_LAYOUT_REVIEW');
  }
}
