import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pdfService } from '@kit.PDFKit';
import probe from 'liboffice_probe.so';
import { PdfRebuildProbe } from '../services/PdfRebuildProbe';

@Entry
@Component
struct Index {
  @State result: string = 'Preparing isolated Office runtime';
  private async copy(context: common.UIAbilityContext, name: string, target: string): Promise<void> {
    const resource = await context.resourceManager.getRawFd(name);
    const output = await fileIo.open(target, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let position: number = 0;
      const buffer = new ArrayBuffer(65536);
      while (position < resource.length) {
        const count = await fileIo.read(resource.fd, buffer,
          { offset: resource.offset + position, length: Math.min(buffer.byteLength, resource.length - position) });
        if (count <= 0) { throw new Error('PROBE_RESOURCE_READ'); }
        let written: number = 0;
        while (written < count) {
          const amount = await fileIo.write(output.fd, buffer.slice(written, count));
          if (amount <= 0) { throw new Error('PROBE_RESOURCE_WRITE'); }
          written += amount;
        }
        position += count;
      }
    } finally { await fileIo.close(output); await context.resourceManager.closeRawFd(name); }
  }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const root = context.filesDir + '/office-probe';
    try {
      if (!await fileIo.access(root)) { await fileIo.mkdir(root, true); }
      if (!await fileIo.access(root + '/program/fundamentalrc')) {
        await this.copy(context, 'office-resources.zip', root + '/resources.zip');
        await zlib.decompressFile(root + '/resources.zip', root);
      }
      await this.copy(context, 'layout.docx', root + '/layout.docx');
      await this.copy(context, 'layout.pptx', root + '/layout.pptx');
      await this.copy(context, 'editable-input.pdf', root + '/editable-input.pdf');
      try { await PdfRebuildProbe.inspect(root); }
      catch (error) { hilog.error(0, 'OfficeStageProbe', 'PDF_REBUILD_FAILURE=%{public}s', String(error)); }
      const config = '<?xml version="1.0"?><fontconfig><dir>' + root + '/fonts</dir>' +
        '<dir>/system/fonts</dir><cachedir>' + root + '/font-cache</cachedir></fontconfig>';
      const configFile = await fileIo.open(root + '/fonts.conf', fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(configFile.fd, config); } finally { await fileIo.close(configFile); }
      this.result = 'Loading LibreOfficeKit';
      hilog.info(0x0000, 'OfficeStageProbe', 'ENGINE_START');
      this.result = await probe.run(root);
      hilog.info(0x0000, 'OfficeStageProbe', 'ENGINE_RESULT=%{public}s', this.result);
      for (const extension of ['docx', 'pptx']) {
        const document = new pdfService.PdfDocument();
        try {
          const status = document.loadDocument(root + '/' + extension + '-output.pdf');
          if (status !== pdfService.ParseResult.PARSE_SUCCESS) { throw new Error('PROBE_PDF_PARSE'); }
          let text: string = '';
          for (let index: number = 0; index < document.getPageCount(); index++) {
            const page = document.getPage(index);
            try { text += page.getTextContent(); } finally { page.release(); }
          }
          hilog.info(0x0000, 'OfficeStageProbe', '%{public}s_PAGES=%{public}d TEXT=%{public}s',
            extension, document.getPageCount(), text);
        } finally { document.releaseDocument(); }
      }
    } catch (error) {
      this.result = 'Office probe failed: ' + String(error);
      hilog.error(0x0000, 'OfficeStageProbe', 'FAILURE=%{public}s', this.result);
      if (await fileIo.access(root + '/engine-stderr.log')) {
        const detail = await fileIo.readText(root + '/engine-stderr.log', { length: 8192 });
        hilog.error(0x0000, 'OfficeStageProbe', 'ENGINE_STDERR=%{public}s', detail);
      }
    }
  }
  aboutToAppear(): void { this.run(); }
  build() { Scroll() { Text(this.result).fontSize(18).padding(24) }.height('100%') }
}
