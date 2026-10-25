'use strict';
// Execute the real bootstrap/verifier against Node file IO and explicitly modeled SDK APIs.
// This tests lifecycle/integrity logic, never OHOS decompression, PDFKit or LibreOffice execution.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { TextEncoder, TextDecoder } = require('node:util');
const { host } = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
const directory = path.join(root, 'tmp/core-engines/runtime-model');
fs.mkdirSync(directory, { recursive: true });
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const cases = [];
function model(options = {}) {
  const cacheDir = fs.mkdtempSync(path.join(directory, 'case-'));
  const entries = [{ name: 'program/unorc', data: Buffer.from('URE_INTERNAL_LIB_DIR=file:///model') },
    { name: 'fonts/test.ttf', data: Buffer.from('model font bytes') }];
  const manifest = Buffer.from(JSON.stringify({ resources: entries.map(entry => ({ name: entry.name,
    sha256: digest(entry.data), byteSize: entry.data.length })) }));
  const archive = Buffer.from('SDK model archive; no decompression proof');
  const raw = { 'office/manifest.json': manifest, 'office/runtime.zip': archive };
  const descriptors = new Set();
  const stats = { rawReads: 0, decompressions: 0, documentReleases: 0, pageReleases: 0, imageReleases: 0 };
  const modes = { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_WRITE: 8 };
  const io = {
    OpenMode: modes,
    open: async (name, flags) => {
      const fd = fs.openSync(name, flags & modes.TRUNC ? 'w' : 'w+');
      descriptors.add(fd); return { fd };
    },
    close: async file => { fs.closeSync(file.fd); descriptors.delete(file.fd); },
    read: async (fd, buffer, spec) => fs.readSync(fd, Buffer.from(buffer), 0,
      Math.min(spec.length, 7), spec.offset),
    write: async (fd, buffer) => {
      const data = typeof buffer === 'string' ? Buffer.from(buffer) : Buffer.from(buffer);
      return fs.writeSync(fd, data, 0, Math.min(data.length, 3));
    },
    access: async name => fs.existsSync(name), readText: async name => fs.readFileSync(name, 'utf8'),
    stat: async name => fs.statSync(name), mkdir: async name => fs.mkdirSync(name, { recursive: true }),
    rmdir: async name => {
      assert.ok(path.resolve(name).startsWith(cacheDir + path.sep));
      fs.rmSync(name, { recursive: true });
    },
    rename: async (from, to) => fs.renameSync(from, to), unlink: async name => fs.unlinkSync(name)
  };
  class PdfDocument {
    constructor() { if (options.constructorFails) throw new Error('modeled constructor failure'); }
    loadDocument() { return options.parseFails ? 1 : 0; }
    isEncrypted(name) { assert.ok(fs.existsSync(name)); return options.encrypted === true; }
    getPageCount() { return options.emptyPages ? 0 : 2; }
    getPage() { return { getTextContent() { if (options.pageFails) throw new Error('modeled corrupt page'); return options.text||''; },
      getGraphicsObjects() {return options.image?[{type:3,pixelMap:{getImageInfo:async()=>({size:{width:options.badImage?0:10,height:10}}),
        release:async()=>{stats.imageReleases++;if(options.releaseFails)throw new Error('modeled image release failure');}}}]:[];}, release() { stats.pageReleases++; } }; }
    releaseDocument() { stats.documentReleases++; }
  }
  const resources = {
    async getRawFd(name) {
      stats.rawReads++;
      const physical = path.join(cacheDir, name.replace('/', '-'));
      // Prefix verifies rawfile byte offsets; short reads and writes verify streaming loops.
      fs.writeFileSync(physical, Buffer.concat([Buffer.from('prefix'), raw[name]]));
      const fd = fs.openSync(physical, 'r'); descriptors.add(fd); this.files.set(name, fd);
      return { fd, offset: 6, length: raw[name].length };
    },
    async closeRawFd(name) { const fd = this.files.get(name); fs.closeSync(fd); descriptors.delete(fd); },
    files: new Map()
  };
  const h = host({ sdkModules: {
    '@kit.CoreFileKit': { fileIo: io, hash: { hash: async name => digest(fs.readFileSync(name)) },
      statfs: { getFreeSize: async () => options.noSpace ? 0 : 1024 ** 3 } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => crypto.randomUUID(),
      TextEncoder: { create: () => ({ encodeInto: value => new TextEncoder().encode(value) }) },
      TextDecoder: { create: () => ({ decodeToString: value => new TextDecoder().decode(value) }) } } },
    '@kit.PDFKit': { pdfService: { PdfDocument, ParseResult: { PARSE_SUCCESS: 0 },GraphicsObjectType:{OBJECT_IMAGE:3} } },
    '@kit.BasicServicesKit': { zlib: { decompressFile: async (_, destination) => {
      stats.decompressions++;
      for (const entry of entries) {
        const name = path.join(destination, entry.name); fs.mkdirSync(path.dirname(name), { recursive: true });
        fs.writeFileSync(name, options.corruptResource ? 'corrupt' : entry.data);
      }
    } } }
  } });
  const bundle = h.load('./generated/OfficeBundle');
  bundle.officeBundleHash = digest(manifest); bundle.officeArchiveHash = digest(archive);
  const runtime = new (h.load('./services/BundledConversionRuntime').BundledConversionRuntime)({ cacheDir, resourceManager: resources });
  const pdf = Buffer.from('%PDF-1.4 modeled artifact, SDK parsing is explicitly mocked');
  const result = { outputs: [{ role: 'primary', formatId: 'pdf', internalRef: 'artifact:' + 'a'.repeat(32),
    byteSize: pdf.length, sha256: options.wrongHash ? 'b'.repeat(64) : digest(pdf) }],
    fidelity: { metrics: [], evidenceRefs: [] } };
  const native = { copyArtifactToFd: async (_, fd) => { fs.writeSync(fd, pdf); return pdf.length; } };
  return { runtime, raw, archive, manifest, stats, cacheDir, result, native, options,
    restart() { return new (h.load('./services/BundledConversionRuntime').BundledConversionRuntime)({ cacheDir, resourceManager: resources }); },
    clean() {
      assert.equal(descriptors.size, 0, 'file descriptor leak');
      assert.ok(!fs.readdirSync(cacheDir).some(name => name.startsWith('pdf-check-')), 'PDF check copy leaked');
      assert.ok(cacheDir.startsWith(directory + path.sep)); fs.rmSync(cacheDir, { recursive: true });
      h.store.shutdown();
    } };
}
async function test(name, fn) { await fn(); cases.push({ name, result: 'passed' }); }
(async () => {
  await test('raw offsets, short reads/writes and concurrent bootstrap reuse', async () => {
    const m = model();
    try {
      await Promise.all([m.runtime.prepareOffice(), m.runtime.prepareOffice()]);
      assert.equal(fs.readFileSync(path.join(m.cacheDir, 'office-runtime/ready.sha256'), 'utf8'), digest(m.manifest));
      assert.ok(fs.readFileSync(path.join(m.cacheDir, 'office-runtime/fonts.conf'), 'utf8').endsWith('</fontconfig>'));
      await m.runtime.prepareOffice(); assert.equal(m.stats.rawReads, 2); assert.equal(m.stats.decompressions, 1);
    } finally { m.clean(); }
  });
  await test('a ready marker cannot hide missing cached engine resources after restart', async () => {
    const m = model();
    try {
      await m.runtime.prepareOffice();
      fs.unlinkSync(path.join(m.cacheDir, 'office-runtime/fonts/test.ttf'));
      await m.restart().prepareOffice();
      assert.equal(fs.readFileSync(path.join(m.cacheDir, 'office-runtime/fonts/test.ttf'), 'utf8'), 'model font bytes');
      assert.equal(m.stats.decompressions, 2);
    } finally { m.clean(); }
  });
  await test('a valid cache tolerates Native bootstrap URL rewrites and avoids extraction', async () => {
    const m = model();
    try {
      await m.runtime.prepareOffice();
      fs.writeFileSync(path.join(m.cacheDir,'office-runtime/program/unorc'),'URE_INTERNAL_LIB_DIR=file:///application/native/libraries');
      await m.restart().prepareOffice();assert.equal(m.stats.decompressions,1);
    } finally { m.clean(); }
  });
  await test('a damaged mutable bootstrap is repaired rather than trusted by its marker', async () => {
    const m = model();
    try {
      await m.runtime.prepareOffice();
      fs.writeFileSync(path.join(m.cacheDir,'office-runtime/program/unorc'),'broken bootstrap');
      await m.restart().prepareOffice();assert.equal(m.stats.decompressions,2);
    } finally { m.clean(); }
  });
  await test('outdated font fallback configuration is replaced after restart', async () => {
    const m = model();
    try {
      await m.runtime.prepareOffice();
      const fontConfig = path.join(m.cacheDir,'office-runtime/fonts.conf');
      fs.writeFileSync(fontConfig,'<fontconfig><dir>/system/fonts</dir></fontconfig>');
      await m.restart().prepareOffice();
      assert.equal(m.stats.decompressions,2);
      assert.ok(fs.readFileSync(fontConfig,'utf8').includes('DejaVu Sans'));
    } finally { m.clean(); }
  });
  for (const kind of ['manifest', 'archive', 'resource']) await test(kind + ' mismatch rolls back and permits retry', async () => {
    const m = model({ corruptResource: kind === 'resource' });
    try {
      if (kind === 'manifest') m.raw['office/manifest.json'] = Buffer.from('corrupt');
      if (kind === 'archive') m.raw['office/runtime.zip'] = Buffer.from('corrupt');
      await assert.rejects(m.runtime.prepareOffice());
      assert.equal(fs.existsSync(path.join(m.cacheDir, 'office-runtime-staging')), false);
      assert.equal(fs.existsSync(path.join(m.cacheDir, 'office-runtime/ready.sha256')), false);
      m.raw['office/manifest.json'] = m.manifest; m.raw['office/runtime.zip'] = m.archive; m.options.corruptResource = false;
      await m.runtime.prepareOffice();
    } finally { m.clean(); }
  });
  await test('insufficient storage fails before copying resources', async () => {
    const m = model({ noSpace: true });
    try { await assert.rejects(m.runtime.prepareOffice(), error => error.code === 'STORAGE_FULL'); assert.equal(m.stats.rawReads, 0); }
    finally { m.clean(); }
  });
  await test('PDF traversal updates evidence without granting a fidelity tier', async () => {
    const m = model();
    try {
      await m.runtime.verifyPdf(m.result, m.native, { maxPages: 100 });
      assert.equal(m.result.validation.state, 'passed'); assert.equal(m.result.fidelity.outputPageCount, 2);
      assert.equal(m.result.fidelity.achievedTier, undefined); assert.equal(m.stats.pageReleases, 2);
      assert.equal(m.stats.documentReleases, 1);
    } finally { m.clean(); }
  });
  for (const setting of ['parseFails', 'encrypted', 'emptyPages', 'pageFails', 'wrongHash', 'constructorFails']) {
    await test(setting + ' rejects PDF and removes temporary copy', async () => {
      const m = model({ [setting]: true });
      try { await assert.rejects(m.runtime.verifyPdf(m.result, m.native, { maxPages: 100 })); }
      finally { m.clean(); }
    });
  }
  for(const setting of ['missingText','missingImages','wrongPageCount']) await test(setting+' refuses an otherwise parseable Office PDF',async()=>{
    const m=model({text:'AB',image:setting!=='missingImages'});
    m.result.contentExpectation={textMinimum:[{codePoint:65,count:1},{codePoint:66,count:1},
      ...(setting==='missingText'?[{codePoint:67,count:1}]:[])],minimumImages:1,pageCount:setting==='wrongPageCount'?3:2};
    try {await assert.rejects(m.runtime.verifyPdf(m.result,m.native,{maxPages:100,maxPixels:1000},'docx'));}
    finally {m.clean();}
  });
  await test('Office content checks tolerate layout text order and Unicode compatibility and release all decoded images',async()=>{
    const m=model({text:' BA ﬁ',image:true});
    m.result.contentExpectation={textMinimum:[{codePoint:65,count:1},{codePoint:66,count:1},
      {codePoint:102,count:1},{codePoint:105,count:1}],minimumImages:1,pageCount:2};
    try {await m.runtime.verifyPdf(m.result,m.native,{maxPages:100,maxPixels:1000},'pptx');
      assert.equal(m.result.contentExpectation,undefined);assert.equal(m.stats.imageReleases,2);
      assert.ok(m.result.fidelity.metrics.some(item=>item.name==='source_text_minimum'&&item.value===1));}
    finally {m.clean();}
  });
  for(const setting of ['badImage','releaseFails']) await test(setting+' rejects the PDF and releases page/document/check copy',async()=>{
    const m=model({image:true,[setting]:true});
    try {await assert.rejects(m.runtime.verifyPdf(m.result,m.native,{maxPages:100,maxPixels:1000}));
      assert.equal(m.stats.pageReleases,1);assert.equal(m.stats.documentReleases,1);assert.equal(m.stats.imageReleases,1);}
    finally {m.clean();}
  });
  await test('an Office result without source expectations is rejected',async()=>{
    const m=model();try {await assert.rejects(m.runtime.verifyPdf(m.result,m.native,{maxPages:100,maxPixels:1000},'docx'),
      error=>error.reason==='OFFICE_CONTENT_EXPECTATION_INVALID');}finally {m.clean();}
  });
  const report = { scope: 'actual ArkTS lifecycle with Node IO and modeled SDK decompression/PDF parser',
    deviceExecution: 'not executed', libreOfficeExecution: 'not executed', passed: cases.length, cases };
  fs.writeFileSync(path.join(root, 'tests/generated/bundled-runtime-regression.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ passed: cases.length, scope: report.scope }));
})().catch(error => { console.error(error); process.exitCode = 1; });
