import { fileIo } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { InputProbe } from '../models/NativeProtocol';
import { OfficePackageWriter, OfficePage, OfficeText } from './OfficePackageWriter';

// Explicit aliases of available fonts, supplied by the engine's font inventory.
// This class never chooses a replacement font.
export interface PdfOfficeFont { pdfName: string; officeName: string; }
export interface PdfOfficeOutput {
  bytes: Uint8Array;
  sourcePages: number;
  textObjects: number;
  imageObjects: number;
  requiresManualReview: boolean;
}

function finite(values: number[]): boolean { return values.every((value: number) => Number.isFinite(value)); }
function equalBox(left: pdfService.PdfRect, right: pdfService.PdfRect): boolean {
  return finite([left.left, left.bottom, left.right, left.top]) &&
    Math.abs(left.left - right.left) < 0.01 && Math.abs(left.bottom - right.bottom) < 0.01 &&
    Math.abs(left.right - right.right) < 0.01 && Math.abs(left.top - right.top) < 0.01;
}
function checkObject(object: pdfService.GraphicsObject, box: pdfService.PdfRect): void {
  if (!Number.isFinite(object.rotate) || object.rotate !== 0) { throw new Error('PDF_ROTATION_UNSUPPORTED'); }
  if (object.fillOpacity !== 1) { throw new Error('PDF_TRANSPARENCY_UNSUPPORTED'); }
  if (!equalBox(object.clipRect, box)) { throw new Error('PDF_CLIPPING_UNSUPPORTED'); }
}
function rebuildText(object: pdfService.TextObject, box: pdfService.PdfRect,
  fonts: PdfOfficeFont[], order: number): OfficeText {
  if (object.charspace !== 0 || object.wordspace !== 0 || object.strokeOpacity !== 0) {
    throw new Error('PDF_TEXT_SPACING_UNSUPPORTED');
  }
  const name: string = (object.fontInfo.fontName ?? '').replace(/^[A-Z]{6}\+/, '');
  const font = fonts.find((entry: PdfOfficeFont) => entry.pdfName === name);
  if (!font) { throw new Error('PDF_FONT_UNAVAILABLE'); }
  if (object.charRects.length === 0 || !Number.isFinite(object.textSize) || object.textSize <= 0 || object.textSize > 400 ||
    !Number.isInteger(object.fillColor) || object.fillColor < 0 || object.fillColor > 0xffffff) {
    throw new Error('PDF_TEXT_GEOMETRY_UNSUPPORTED');
  }
  let left: number = box.right;
  let right: number = box.left;
  let top: number = box.bottom;
  let bottom: number = box.top;
  for (const rectangle of object.charRects) {
    if (!finite([rectangle.left, rectangle.right, rectangle.top, rectangle.bottom]) ||
      rectangle.right < rectangle.left || rectangle.top < rectangle.bottom) { throw new Error('PDF_TEXT_GEOMETRY_UNSUPPORTED'); }
    left = Math.min(left, rectangle.left); right = Math.max(right, rectangle.right);
    top = Math.max(top, rectangle.top); bottom = Math.min(bottom, rectangle.bottom);
  }
  if (left < box.left || right > box.right || bottom < box.bottom || top > box.top || right <= left || top <= bottom ||
    /[\r\n]/.test(object.text)) { throw new Error('PDF_TEXT_GEOMETRY_UNSUPPORTED'); }
  // Glyph bounds locate the text; Office line metrics still require reference-render review.
  return { text: object.text, x: left, y: box.top - top, width: right - left,
    height: Math.max(top - bottom, object.textSize * 1.25), font: font.officeName,
    size: object.textSize, color: object.fillColor.toString(16).padStart(6, '0'), zIndex: order };
}

// Experimental backend only. The main route whitelist is deliberately unchanged.
// Supported subset: unencrypted, unrotated pages; available fonts; text and images.
// Caller must bind a trusted, completed protection probe to this exact sandbox copy.
// PDFKit.isEncrypted alone does not establish absence of signatures or DRM.
export class PdfOfficeConverter {
  static async convert(sourcePath: string, target: string, fonts: PdfOfficeFont[], probe: InputProbe,
    checkControl: () => void): Promise<PdfOfficeOutput> {
    if (target !== 'docx' && target !== 'pptx') { throw new Error('PDF_TARGET_UNSUPPORTED'); }
    if (probe.actualFormatId !== 'pdf' || probe.protection !== 'none' || probe.needsDeepCheck) {
      throw new Error('PDF_PREFLIGHT_REQUIRED');
    }
    if (!sourcePath.startsWith('/') || sourcePath.split('/').includes('..')) { throw new Error('PDF_SOURCE_PATH'); }
    checkControl();
    const stat = await fileIo.stat(sourcePath);
    if (!Number.isInteger(stat.size) || stat.size <= 0 || stat.size > 100 * 1024 * 1024) { throw new Error('PDF_INPUT_LIMIT'); }
    const document = new pdfService.PdfDocument();
    const pages: OfficePage[] = [];
    let textCount: number = 0;
    let imageCount: number = 0;
    let objectCount: number = 0;
    let imageBytes: number = 0;
    try {
      if (document.isEncrypted(sourcePath)) { throw new Error('PDF_PROTECTED'); }
      checkControl();
      if (document.loadDocument(sourcePath) !== pdfService.ParseResult.PARSE_SUCCESS) { throw new Error('PDF_PARSE_FAILED'); }
      const count: number = document.getPageCount();
      if (!Number.isInteger(count) || count < 1 || count > 100) { throw new Error('PDF_PAGE_LIMIT'); }
      for (let index: number = 0; index < count; index++) {
        checkControl();
        const page = document.getPage(index);
        let objects: pdfService.GraphicsObject[] = [];
        try {
          if (page.getRotation() !== pdfService.RotationAngle.ANGLE_0) { throw new Error('PDF_ROTATION_UNSUPPORTED'); }
          if (page.getAnnotations().length !== 0) { throw new Error('PDF_ANNOTATIONS_UNSUPPORTED'); }
          const box = page.getBox(pdfService.BoxType.BOX_MEDIA);
          if (!finite([box.left, box.bottom, box.right, box.top]) || box.left !== 0 || box.bottom !== 0 ||
            box.right <= 0 || box.top <= 0 || box.right > 14400 || box.top > 14400 ||
            !equalBox(page.getBox(pdfService.BoxType.BOX_CROP), box)) { throw new Error('PDF_PAGE_GEOMETRY_UNSUPPORTED'); }
          const rebuilt: OfficePage = { width: box.right, height: box.top, texts: [], images: [] };
          objects = page.getGraphicsObjects();
          objectCount += objects.length;
          if (objectCount > 5000) { throw new Error('PDF_OBJECT_LIMIT'); }
          for (let order: number = 0; order < objects.length; order++) {
            checkControl();
            const object = objects[order];
            if (object.type === pdfService.GraphicsObjectType.OBJECT_TEXT) {
              checkObject(object, box);
              const text = object as pdfService.TextObject;
              if (text.text.length === 0) { continue; }
              rebuilt.texts.push(rebuildText(text, box, fonts, order)); textCount++;
            } else if (object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE) {
              const picture = object as pdfService.ImageObject;
              checkObject(object, box);
              if (!finite([picture.x, picture.y, picture.width, picture.height]) || picture.x < 0 || picture.y < 0 ||
                picture.width <= 0 || picture.height <= 0 || picture.x + picture.width > box.right ||
                picture.y + picture.height > box.top) { throw new Error('PDF_IMAGE_GEOMETRY_UNSUPPORTED'); }
              const information = await picture.pixelMap.getImageInfo();
              if (!Number.isInteger(information.size.width) || !Number.isInteger(information.size.height) ||
                information.size.width <= 0 || information.size.height <= 0 ||
                information.size.width * information.size.height > 16000000) { throw new Error('PDF_IMAGE_PIXEL_LIMIT'); }
              const packer = image.createImagePacker();
              let encoded: ArrayBuffer;
              try { encoded = await packer.packing(picture.pixelMap, { format: 'image/png', quality: 100 }); }
              finally { await packer.release(); }
              checkControl();
              imageBytes += encoded.byteLength;
              if (imageBytes > 8 * 1024 * 1024) { throw new Error('PDF_IMAGE_BYTE_LIMIT'); }
              rebuilt.images.push({ png: new Uint8Array(encoded), x: picture.x, y: box.top - picture.y - picture.height,
                width: picture.width, height: picture.height, zIndex: order }); imageCount++;
            } else { throw new Error('PDF_OBJECT_UNSUPPORTED'); }
          }
          const extracted = rebuilt.texts.map((text: OfficeText) => text.text).join('').replace(/\s/g, '');
          if (extracted !== page.getTextContent().replace(/\s/g, '')) { throw new Error('PDF_TEXT_EXTRACTION_MISMATCH'); }
          pages.push(rebuilt);
        } finally {
          try {
            const releases: Promise<void>[] = objects
              .filter((object: pdfService.GraphicsObject) => object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE)
              .map((object: pdfService.GraphicsObject) => (object as pdfService.ImageObject).pixelMap.release());
            const results = await Promise.allSettled(releases);
            if (results.some((result: PromiseSettledResult<void>) => result.status === 'rejected')) {
              throw new Error('PDF_IMAGE_RELEASE_FAILED');
            }
          } finally { page.release(); }
        }
      }
    } finally { document.releaseDocument(); }
    if (textCount === 0 && imageCount > 0) { throw new Error('PDF_OCR_REQUIRED'); }
    checkControl();
    const bytes: Uint8Array = target === 'docx' ? OfficePackageWriter.docx(pages) : OfficePackageWriter.pptx(pages);
    checkControl();
    return { bytes, sourcePages: pages.length, textObjects: textCount, imageObjects: imageCount, requiresManualReview: true };
  }
}
