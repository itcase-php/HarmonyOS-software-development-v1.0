'use strict';
// Real converter/OOXML code with modeled SDK calls; no device or rendering claims.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { host } = require('./check-interactions.cjs');
const png = new Uint8Array(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQsZkGAAFOAOdnZDkrAAAAAElFTkSuQmCC', 'base64'));
const bounds = { left: 0, bottom: 0, right: 612, top: 792 };
function fixture(options = {}) {
  const events = [];
  const text = { type: 1, x: 40, y: 700, rotate: 0, clipRect: bounds, fillColor: 0x123456,
    fillOpacity: 1, strokeOpacity: 0, text: 'Editable 12345', textSize: 20,
    fontInfo: { fontName: 'ABCDEF+DejaVuSans' }, charspace: 0, wordspace: 0,
    charRects: [{ left: 40, bottom: 700, right: 200, top: 720 }], ...options.text };
  const image = { type: 3, x: 40, y: 400, width: 240, height: 100, rotate: 0,
    clipRect: bounds, fillOpacity: 1, strokeOpacity: 0,
    pixelMap: { getImageInfo: async () => ({ size: { width: 1, height: 1 } }), release: async () => events.push('pixel-release') } };
  const page = { getBox: () => bounds, getRotation: () => options.rotation || 0,
    getAnnotations: () => options.annotations || [], getGraphicsObjects: () => options.objects || (options.textFirst ? [text, image] : [image, text]),
    getTextContent: () => options.pageText || text.text, release: () => events.push('page-release') };
  const sdkModules = {
    '@kit.CoreFileKit': { fileIo: { stat: async () => ({ size: options.inputSize || 1000 }) } },
    '@kit.PDFKit': { pdfService: { ParseResult: { PARSE_SUCCESS: 0 }, BoxType: { BOX_MEDIA: 0, BOX_CROP: 1 },
      RotationAngle: { ANGLE_0: 0 }, GraphicsObjectType: { OBJECT_TEXT: 1, OBJECT_IMAGE: 3 }, PdfDocument: class {
        isEncrypted() { return options.encrypted === true; }
        loadDocument() { events.push('load'); return options.parseFailure ? 1 : 0; }
        getPageCount() { return options.pageCount || 2; }
        getPage() { return page; }
        releaseDocument() { events.push('document-release'); }
      } } },
    '@kit.ImageKit': { image: { createImagePacker: () => ({
      packing: async () => { if (options.packFailure) throw new Error('PACK_FAILED'); return png.buffer; },
      release: async () => events.push('packer-release')
    }) } }
  };
  const { PdfOfficeConverter } = host({ sdkModules }).load('./services/PdfOfficeConverter');
  const fonts = options.fonts || [{ pdfName: 'DejaVuSans', officeName: 'DejaVu Sans' }];
  const probe = { fileId: 'host-fixture', actualFormatId: 'pdf', protection: 'none', needsDeepCheck: false, ...options.probe };
  return { events, convert: (target, control = () => {}) => PdfOfficeConverter.convert('/sandbox/source.pdf', target, fonts, probe, control) };
}
(async () => {
  const output = path.resolve(__dirname, '../tmp/offline-engines/pdf-office-tests');
  fs.mkdirSync(output, { recursive: true });
  for (const target of ['docx', 'pptx']) {
    const test = fixture(), result = await test.convert(target);
    assert.equal(result.sourcePages, 2);
    assert.equal(result.textObjects, 2);
    assert.equal(result.imageObjects, 2);
    assert.equal(result.requiresManualReview, true);
    assert.equal(Buffer.from(result.bytes).readUInt32LE(0), 0x04034b50);
    assert.equal(test.events.filter(event => event === 'page-release').length, 2);
    assert.equal(test.events.filter(event => event === 'pixel-release').length, 2);
    assert.ok(test.events.includes('document-release'));
    fs.writeFileSync(path.join(output, 'rebuilt.' + target), result.bytes);
  }
  for (const [options, expected] of [
    [{ encrypted: true }, /PDF_PROTECTED/], [{ parseFailure: true }, /PDF_PARSE_FAILED/],
    [{ rotation: 90 }, /PDF_ROTATION_UNSUPPORTED/], [{ annotations: [{}] }, /PDF_ANNOTATIONS_UNSUPPORTED/],
    [{ fonts: [], textFirst: true }, /PDF_FONT_UNAVAILABLE/], [{ text: { rotate: 45 } }, /PDF_ROTATION_UNSUPPORTED/],
    [{ text: { charspace: 2 } }, /PDF_TEXT_SPACING_UNSUPPORTED/],
    [{ text: { fillOpacity: 0.5 } }, /PDF_TRANSPARENCY_UNSUPPORTED/],
    [{ text: { clipRect: { left: 50, right: 100, top: 720, bottom: 700 } } }, /PDF_CLIPPING_UNSUPPORTED/],
    [{ objects: [{ type: 2 }] }, /PDF_OBJECT_UNSUPPORTED/], [{ pageCount: 101 }, /PDF_PAGE_LIMIT/],
    [{ inputSize: 101 * 1024 * 1024 }, /PDF_INPUT_LIMIT/],
    [{ packFailure: true }, /PACK_FAILED/], [{ pageText: 'Missing text' }, /PDF_TEXT_EXTRACTION_MISMATCH/]
  ]) {
    const test = fixture(options);
    await assert.rejects(test.convert('docx'), expected);
    if (!options.inputSize) assert.ok(test.events.includes('document-release'));
    if (options.textFirst) assert.ok(test.events.includes('pixel-release'), 'unprocessed image handles must be released');
    if (options.packFailure) {
      assert.ok(test.events.includes('packer-release'));
      assert.ok(test.events.includes('pixel-release'));
      assert.ok(test.events.includes('page-release'));
    }
  }
  const cancelled = fixture();
  await assert.rejects(cancelled.convert('docx', () => { throw new Error('CANCELLED'); }), /CANCELLED/);
  assert.ok(!cancelled.events.includes('load'));
  await assert.rejects(fixture().convert('pdf'), /PDF_TARGET_UNSUPPORTED/);
  for (const probe of [{ protection: 'signed' }, { protection: 'drm' }, { protection: 'unknown' },
    { needsDeepCheck: true }, { actualFormatId: 'jpeg' }]) {
    const test = fixture({ probe });
    await assert.rejects(test.convert('docx'), /PDF_PREFLIGHT_REQUIRED/);
    assert.ok(!test.events.includes('load'));
  }
  console.log('PDF to editable Office: 2 modeled SDK conversion flows and 21 failure/control cases passed; device and layout validation pending.');
})().catch(error => { console.error(error); process.exitCode = 1; });
