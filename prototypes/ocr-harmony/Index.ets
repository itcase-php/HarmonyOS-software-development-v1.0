import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import probe from 'libhdm_ocr_probe.so';

// Standalone test app template, not a converter page or a production route.
@Entry
@Component
struct Index {
  @State result: string = 'Offline OCR probe ready';
  @State running: boolean = false;
  private async copyResource(context: common.UIAbilityContext, resource: string, target: string): Promise<void> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(resource);
    await this.writeBytes(bytes, target);
  }
  private async writeBytes(bytes: Uint8Array, target: string): Promise<void> {
    const file = await fileIo.open(target, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let written: number = 0;
      while (written < bytes.byteLength) {
        const count: number = await fileIo.write(file.fd, bytes.slice(written).buffer);
        if (count <= 0) { throw new Error('PROBE_RESOURCE_WRITE_FAILED'); }
        written += count;
      }
    } finally { await fileIo.close(file); }
  }
  private async run(): Promise<void> {
    if (this.running) { return; }
    this.running = true; this.result = 'Loading bundled offline models';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const root: string = context.cacheDir + '/ocr-probe';
      if (!await fileIo.access(root)) { await fileIo.mkdir(root, true); }
      await this.copyResource(context, 'eng.traineddata', root + '/eng.traineddata');
      await this.copyResource(context, 'chi_sim.traineddata', root + '/chi_sim.traineddata');
      await this.copyResource(context, 'ocr-fixture.pgm', root + '/input.pgm');
      this.result = await probe.run(root, root + '/input.pgm');
    } catch (_) { this.result = 'OCR probe failed; inspect the test log'; }
    finally { this.running = false; }
  }
  private async inspectPdf(): Promise<void> {
    if (this.running) { return; }
    this.running = true;
    const document = new pdfService.PdfDocument();
    let phase: string = 'copy';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const input = context.cacheDir + '/pdf-fixture.pdf';
      await this.copyResource(context, 'pdf-fixture.pdf', input);
      phase = 'parse';
      const parsed = document.loadDocument(input);
      if (parsed !== pdfService.ParseResult.PARSE_SUCCESS || document.getPageCount() !== 2) {
        throw new Error('PROBE_PDF_PARSE_FAILED');
      }
      let summary: string = 'PDFKit: 2 pages loaded';
      for (let index: number = 0; index < 2; index++) {
        const page = document.getPage(index);
        try {
          const objects = page.getGraphicsObjects();
          const text = objects.filter(item => item.type === pdfService.GraphicsObjectType.OBJECT_TEXT)
            .map(item => (item as pdfService.TextObject).text).join('');
          phase = 'render';
          const raster = page.getPagePixelMap();
          try {
            const info = await raster.getImageInfo();
            summary += `\npage=${index + 1} objects=${objects.length} text=${text} render=${info.size.width}x${info.size.height}`;
            if (index === 1) {
              // This bounded fixture is grayscale. Do not treat this as a general image adapter.
              if (info.size.width !== 1400 || info.size.height !== 260 ||
                (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 && info.pixelFormat !== image.PixelMapFormat.BGRA_8888)) {
                phase = `pixelFormat=${info.pixelFormat} dimensions=${info.size.width}x${info.size.height}`;
                throw new Error('PROBE_PIXEL_FORMAT');
              }
              phase = 'readPixels';
              const pixels = new Uint8Array(1400 * 260 * 4);
              await raster.readPixelsToBuffer(pixels.buffer);
              const header: string = 'P5\n1400 260\n255\n';
              const pgm = new Uint8Array(header.length + 1400 * 260);
              for (let offset: number = 0; offset < header.length; offset++) { pgm[offset] = header.charCodeAt(offset); }
              for (let offset: number = 0; offset < 1400 * 260; offset++) { pgm[header.length + offset] = pixels[offset * 4]; }
              const root: string = context.cacheDir + '/ocr-probe';
              phase = 'modelDirectory';
              if (!await fileIo.access(root)) { await fileIo.mkdir(root, true); }
              await this.copyResource(context, 'eng.traineddata', root + '/eng.traineddata');
              await this.copyResource(context, 'chi_sim.traineddata', root + '/chi_sim.traineddata');
              await this.writeBytes(pgm, root + '/pdf-render.pgm');
              phase = 'ocr';
              summary += '\nRendered scan OCR:\n' + await probe.run(root, root + '/pdf-render.pgm');
            }
          } finally { await raster.release(); }
        } finally { page.release(); }
      }
      this.result = summary;
    } catch (_) { this.result = 'PDFKit probe failed at ' + phase + '; no production route is enabled'; }
    finally { document.releaseDocument(); this.running = false; }
  }
  build() {
    Column({ space: 20 }) {
      Text('HarmonyOS offline OCR feasibility').fontSize(24)
      Button('Run bundled English + Chinese fixture').enabled(!this.running).onClick(() => { this.run(); })
      Button('Inspect bundled text + scan PDF with PDFKit').enabled(!this.running).onClick(() => { this.inspectPdf(); })
      Text(this.result).fontSize(18)
    }.width('100%').padding(32)
  }
}
