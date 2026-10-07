'use strict';
// OOXML writer contract only; parsing these packages does not prove PDF fidelity.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { host } = require('./check-interactions.cjs');
const { OfficePackageWriter } = host().load('./services/OfficePackageWriter');
const output = path.resolve(__dirname, '../tmp/offline-engines/package-tests');
fs.mkdirSync(output, { recursive: true });
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQsZkGAAFOAOdnZDkrAAAAAElFTkSuQmCC', 'base64');
const text = { text: '\u4e2d\u6587 \ud83d\ude00 <&> 12345\nSecond line', x: 30, y: 40, width: 400, height: 60,
  font: 'DejaVu Sans', size: 18, color: '123456', zIndex: 1 };
const page = { width: 612, height: 792, texts: [text], images: [{ png: new Uint8Array(png), x: 50, y: 100, width: 20, height: 20, zIndex: 0 }] };
function entries(bytes) {
  const buffer = Buffer.from(bytes), parts = new Map();
  let position = 0;
  while (buffer.readUInt32LE(position) === 0x04034b50) {
    assert.equal(buffer.readUInt16LE(position + 8), 0, 'fixture packages use STORE');
    const size = buffer.readUInt32LE(position + 18);
    const nameLength = buffer.readUInt16LE(position + 26), extra = buffer.readUInt16LE(position + 28);
    const name = buffer.subarray(position + 30, position + 30 + nameLength).toString('utf8');
    const start = position + 30 + nameLength + extra;
    assert.ok(!parts.has(name), 'duplicate package part');
    parts.set(name, buffer.subarray(start, start + size));
    position = start + size;
  }
  assert.equal(buffer.readUInt32LE(position), 0x02014b50);
  assert.equal(buffer.readUInt32LE(buffer.length - 22), 0x06054b50);
  assert.equal(buffer.readUInt16LE(buffer.length - 12), parts.size);
  return parts;
}
for (const format of ['docx', 'pptx']) {
  const bytes = OfficePackageWriter[format]([page, { ...page, images: [] }]);
  const parts = entries(bytes);
  const xml = [...parts].filter(([name]) => name.endsWith('.xml')).map(([, value]) => value.toString('utf8')).join('');
  assert.ok(xml.includes('\u4e2d\u6587 \ud83d\ude00 &lt;&amp;&gt; 12345'));
  assert.ok(xml.includes('DejaVu Sans'));
  const media = [...parts].filter(([name]) => name.endsWith('.png'));
  assert.equal(media.length, 1);
  assert.deepEqual(media[0][1], png);
  assert.ok(format === 'docx' ? xml.includes('w:txbxContent') : xml.includes('p:txBody'));
  assert.ok(xml.includes(format === 'docx' ? '<w:br/>' : '<a:br/>'), 'line breaks must use editable OOXML breaks');
  assert.ok(format === 'docx' ? xml.indexOf('<v:imagedata') < xml.indexOf('<w:txbxContent') :
    xml.indexOf('<p:pic>') < xml.indexOf('<p:sp>'), 'background images must stay behind text');
  fs.writeFileSync(path.join(output, `editable.${format}`), bytes);
  assert.throws(() => OfficePackageWriter[format]([]), /OFFICE_PAGE_LIMIT/);
  assert.throws(() => OfficePackageWriter[format]([{ ...page, width: NaN }]), /OFFICE_PAGE_SIZE/);
  assert.throws(() => OfficePackageWriter[format]([{ ...page, texts: [{ ...text, x: -1 }] }]), /OFFICE_OBJECT_BOUNDS/);
  assert.throws(() => OfficePackageWriter[format]([{ ...page, texts: [{ ...text, text: '\u0001' }] }]), /OFFICE_XML_CONTROL/);
  assert.throws(() => OfficePackageWriter[format]([{ ...page, texts: [{ ...text, text: '\ud800' }] }]), /OFFICE_INVALID_UNICODE/);
  assert.throws(() => OfficePackageWriter[format]([{ ...page, images: [{ ...page.images[0], png: new Uint8Array(24) }] }]), /OFFICE_IMAGE_INVALID/);
}
assert.throws(() => OfficePackageWriter.pptx([page, { ...page, width: 792 }]), /OFFICE_MIXED_SLIDE_SIZES/);
console.log('OOXML writer: Unicode, editable objects, embedded images, ZIP structure and invalid inputs passed. Device rendering remains required.');
