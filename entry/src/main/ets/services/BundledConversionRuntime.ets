import { common } from '@kit.AbilityKit';
import { fileIo, hash, statfs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { pdfService } from '@kit.PDFKit';
import { util } from '@kit.ArkTS';
import { officeBundleHash, officeArchiveHash } from '../generated/OfficeBundle';
import { ConvertResult, NativeModule, ResourceBudget } from '../models/NativeProtocol';
import { BridgeError } from '../common/BridgeError';
import { ErrorHandler } from '../common/ErrorHandler';
import { ConversionRuntimePort } from './ConversionRuntimeContracts';

interface ResourceEntry { name: string; sha256: string; byteSize: number; }
interface OfficeManifest { resources: ResourceEntry[]; }

export class BundledConversionRuntime implements ConversionRuntimePort {
  private preparing: Promise<void> | null = null;
  private context: common.Context;
  constructor(context: common.Context) { this.context = context; }
  async prepareOffice(): Promise<void> {
    if (!this.preparing) { this.preparing = this.prepare(); }
    try { await this.preparing; }
    catch (error) { this.preparing = null; throw ErrorHandler.catchBridge(error, 'Office.prepare', 'ENGINE_MISSING', 'OFFICE_RESOURCE_PREPARATION_FAILED'); }
  }
  private async copy(name: string, target: string): Promise<void> {
    const resource = await this.context.resourceManager.getRawFd(name);
    let output: fileIo.File | null = null;
    try {
      output = await fileIo.open(target, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      const buffer = new ArrayBuffer(256 * 1024);
      let position: number = 0;
      while (position < resource.length) {
        const count = await fileIo.read(resource.fd, buffer,
          { offset: resource.offset + position, length: Math.min(buffer.byteLength, resource.length - position) });
        if (count <= 0) { throw new BridgeError('IO_ERROR', 'OFFICE_RESOURCE_READ'); }
        let written: number = 0;
        while (written < count) {
          const amount = await fileIo.write(output.fd, buffer.slice(written, count));
          if (amount <= 0) { throw new BridgeError('IO_ERROR', 'OFFICE_RESOURCE_WRITE'); }
          written += amount;
        }
        position += count;
      }
    } finally {
      try { if (output) { await fileIo.close(output); } }
      finally { await this.context.resourceManager.closeRawFd(name); }
    }
  }
  private async write(path: string, value: string): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes = util.TextEncoder.create('utf-8').encodeInto(value);
      let position: number = 0;
      while (position < bytes.byteLength) {
        const count = await fileIo.write(file.fd, bytes.slice(position).buffer);
        if (count <= 0) { throw new BridgeError('IO_ERROR', 'OFFICE_RESOURCE_WRITE'); }
        position += count;
      }
    } finally { await fileIo.close(file); }
  }
  private fontConfig(root: string): string {
    const escaped = root.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
    return '<?xml version="1.0"?><fontconfig><dir>' + escaped +
      '/fonts</dir><dir>/system/fonts</dir><cachedir>' + escaped + '/font-cache</cachedir>' +
      '<match target="pattern"><edit name="family" mode="append" binding="weak">' +
      '<string>DejaVu Sans</string></edit></match></fontconfig>';
  }
  private async prepare(): Promise<void> {
    const root = this.context.cacheDir + '/office-runtime';
    const staging = this.context.cacheDir + '/office-runtime-staging';
    // A marker alone does not prove the OS retained all cache files.
    if (await this.cachedResourcesValid(root)) { return; }
    if (await statfs.getFreeSize(this.context.cacheDir) < 400 * 1024 * 1024) {
      throw new BridgeError('STORAGE_FULL', 'OFFICE_RESOURCE_STORAGE');
    }
    if (await fileIo.access(staging)) { await fileIo.rmdir(staging); }
    await fileIo.mkdir(staging, true);
    try {
      await this.copy('office/manifest.json', staging + '/manifest.json');
      if ((await hash.hash(staging + '/manifest.json', 'sha256')).toLowerCase() !== officeBundleHash) {
        throw new BridgeError('ENGINE_MISSING', 'OFFICE_MANIFEST_MISMATCH');
      }
      const manifest = JSON.parse(await fileIo.readText(staging + '/manifest.json')) as OfficeManifest;
      await this.copy('office/runtime.zip', staging + '/runtime.zip');
      if ((await hash.hash(staging + '/runtime.zip', 'sha256')).toLowerCase() !== officeArchiveHash) {
        throw new BridgeError('ENGINE_MISSING', 'OFFICE_ARCHIVE_MISMATCH');
      }
      await zlib.decompressFile(staging + '/runtime.zip', staging);
      for (const entry of manifest.resources) {
        if (entry.name.startsWith('/') || entry.name.includes('..') || entry.name.includes('\\')) {
          throw new BridgeError('ENGINE_MISSING', 'OFFICE_RESOURCE_PATH');
        }
        const path = staging + '/' + entry.name;
        const stat = await fileIo.stat(path);
        if (!stat.isFile() || stat.size !== entry.byteSize ||
          (await hash.hash(path, 'sha256')).toLowerCase() !== entry.sha256) {
          throw new BridgeError('ENGINE_MISSING', 'OFFICE_RESOURCE_MISMATCH');
        }
      }
      await fileIo.unlink(staging + '/runtime.zip');
      // Fixed sandbox path; only this service owns both directories.
      if (await fileIo.access(root)) { await fileIo.rmdir(root); }
      await fileIo.rename(staging, root);
      await this.write(root + '/fonts.conf', this.fontConfig(root));
      await this.write(root + '/ready.sha256', officeBundleHash);
    } catch (error) {
      if (await fileIo.access(staging)) { await fileIo.rmdir(staging); }
      throw ErrorHandler.catchBridge(error, 'Office.resources', 'ENGINE_MISSING', 'OFFICE_RESOURCE_PREPARATION_FAILED');
    }
  }
  private async cachedResourcesValid(root: string): Promise<boolean> {
    try {
      if (!await fileIo.access(root + '/ready.sha256') ||
        await fileIo.readText(root + '/ready.sha256') !== officeBundleHash ||
        (await hash.hash(root + '/manifest.json', 'sha256')).toLowerCase() !== officeBundleHash ||
        !await fileIo.access(root + '/fonts.conf') ||
        await fileIo.readText(root + '/fonts.conf') !== this.fontConfig(root)) { return false; }
      const manifest = JSON.parse(await fileIo.readText(root + '/manifest.json')) as OfficeManifest;
      for (const entry of manifest.resources) {
        const path = root + '/' + entry.name;
        const stat = await fileIo.stat(path);
        if (!stat.isFile()) { return false; }
        // Native rewrites library URLs in these two verified bootstrap files.
        if (entry.name === 'program/fundamentalrc' || entry.name === 'program/unorc') {
          if (stat.size === 0) { return false; }
          const requiredKey = entry.name === 'program/unorc' ? 'URE_INTERNAL_LIB_DIR=' : 'LO_LIB_DIR=';
          if (!(await fileIo.readText(path)).includes(requiredKey)) { return false; }
        } else if (stat.size !== entry.byteSize ||
          (await hash.hash(path, 'sha256')).toLowerCase() !== entry.sha256) { return false; }
      }
      return true;
    } catch (error) { return false; }
  }
  private addText(text: string, counts: Map<number, number>, multiplier: number = 1): void {
    for (const character of text.normalize('NFKD')) {
      const cp = character.codePointAt(0) ?? 0;
      if (cp <= 32 || cp === 0xa0 || cp === 0xad || (cp >= 0x2000 && cp <= 0x200f) ||
        (cp >= 0x2028 && cp <= 0x202f) || (cp >= 0x2060 && cp <= 0x206f) || cp === 0xfeff) { continue; }
      counts.set(cp, (counts.get(cp) ?? 0) + multiplier);
    }
  }
  async verifyPdf(result: ConvertResult, native: NativeModule, budget: ResourceBudget, sourceFormatId?: string): Promise<void> {
    const artifact = result.outputs.find((item) => item.role === 'primary' && item.formatId === 'pdf');
    if (!artifact) { throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'PDF_PRIMARY_MISSING'); }
    const path = this.context.cacheDir + '/pdf-check-' + util.generateRandomUUID() + '.pdf';
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
    let document: pdfService.PdfDocument | null = null;
    try {
      const expected = result.contentExpectation;
      const office = sourceFormatId === 'docx' || sourceFormatId === 'pptx';
      if (office && (!expected || !Array.isArray(expected.textMinimum) || expected.textMinimum.length > 8192 ||
        !Number.isSafeInteger(expected.minimumImages) || expected.minimumImages < 0 || expected.minimumImages > 4096)) {
        throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'OFFICE_CONTENT_EXPECTATION_INVALID');
      }
      const required: Map<number, number> = new Map<number, number>();
      if (expected) {
        const seen: Set<number> = new Set<number>(); let total: number = 0;
        for (const item of expected.textMinimum) {
          if (!Number.isSafeInteger(item.codePoint) || item.codePoint < 0 || item.codePoint > 0x10ffff ||
            (item.codePoint >= 0xd800 && item.codePoint <= 0xdfff) || seen.has(item.codePoint) ||
            !Number.isSafeInteger(item.count) || item.count <= 0 || (total += item.count) > 1000000) {
            throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'OFFICE_CONTENT_EXPECTATION_INVALID');
          }
          seen.add(item.codePoint); this.addText(String.fromCodePoint(item.codePoint), required, item.count);
        }
      }
      document = new pdfService.PdfDocument();
      const bytes = await native.copyArtifactToFd(artifact.internalRef, file.fd, artifact.sha256, artifact.byteSize);
      if (bytes !== artifact.byteSize || (await hash.hash(path, 'sha256')).toLowerCase() !== artifact.sha256 ||
        document.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS || document.isEncrypted(path)) {
        throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'PDF_PARSER_REJECTED');
      }
      const count = document.getPageCount();
      if (count <= 0 || count > budget.maxPages) { throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'PDF_PAGE_LIMIT'); }
      if (expected?.pageCount !== undefined && (!Number.isSafeInteger(expected.pageCount) || expected.pageCount !== count)) {
        throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'OFFICE_PAGE_COUNT_MISMATCH');
      }
      const found: Map<number, number> = new Map<number, number>(); let images: number = 0;
      for (let index: number = 0; index < count; index++) {
        const page = document.getPage(index);
        let objects: pdfService.GraphicsObject[] = [];
        try {
          // Traversal forces page content parsing; neither this nor text extraction grades layout fidelity.
          this.addText(page.getTextContent(), found); objects = page.getGraphicsObjects();
          let pixels: number = 0;
          for (const object of objects) {
            if (object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE) {
              const info = await (object as pdfService.ImageObject).pixelMap.getImageInfo();
              pixels += info.size.width * info.size.height;
              if (!Number.isSafeInteger(info.size.width) || !Number.isSafeInteger(info.size.height) ||
                info.size.width <= 0 || info.size.height <= 0 || pixels > budget.maxPixels) {
                throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'PDF_IMAGE_INVALID_OR_LIMIT');
              }
              images++;
            }
          }
        } finally {
          try {
            const released = await Promise.allSettled(objects
              .filter((object: pdfService.GraphicsObject) => object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE)
              .map(async (object: pdfService.GraphicsObject): Promise<void> => { await (object as pdfService.ImageObject).pixelMap.release(); }));
            if (released.some((item: PromiseSettledResult<void>) => item.status === 'rejected')) {
              throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'PDF_IMAGE_RELEASE_FAILED');
            }
          } finally { page.release(); }
        }
      }
      for (const entry of required.entries()) {
        if ((found.get(entry[0]) ?? 0) < entry[1]) { throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'OFFICE_TEXT_MISSING'); }
      }
      if (expected && images < expected.minimumImages) {
        throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'OFFICE_IMAGES_MISSING');
      }
      result.validation = { state: 'passed', validatorVersion: 'pdfkit-document-pages-v1',
        evidenceRefs: ['pdfkit-independent-parse', 'page-content-traversal', 'artifact-sha256-verified'] };
      if (result.fidelity) {
        result.fidelity.outputPageCount = count;
        result.fidelity.metrics.push({ name: 'output_page_count', state: 'measured', value: count, unit: 'count',
          algorithmVersion: 'pdfkit-page-count-v1', evidenceRefs: ['pdfkit-independent-parse'] });
        result.fidelity.evidenceRefs.push('pdfkit-independent-parse');
        if (office && required.size > 0) {
          result.fidelity.metrics.push({ name: 'source_text_minimum', state: 'measured', value: 1, unit: 'ratio',
            algorithmVersion: 'ooxml-pdfkit-normalized-character-minimum-v1', evidenceRefs: ['source-body-text-minimum'] });
          result.fidelity.evidenceRefs.push('source-body-text-minimum');
        }
      }
      result.contentExpectation = undefined;
    } finally {
      try { if (document) { document.releaseDocument(); } }
      finally { try { await fileIo.close(file); } finally { await fileIo.unlink(path); } }
    }
  }
}
