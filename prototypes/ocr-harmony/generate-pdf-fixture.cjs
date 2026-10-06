'use strict';
// Public synthetic corpus: one text page and one raster page. No user documents.
const fs = require('node:fs');
const path = require('node:path');
const root = process.argv[2];
if (!root) throw new Error('Provide the test app rawfile directory');
const pgm = fs.readFileSync(path.join(root, 'ocr-fixture.pgm'));
const header = Buffer.from('P5\n1400 260\n255\n');
if (!pgm.subarray(0, header.length).equals(header) || pgm.length !== header.length + 1400 * 260) {
  throw new Error('Unexpected generated PGM');
}
function stream(dictionary, data) {
  return Buffer.concat([Buffer.from(`<< ${dictionary} /Length ${data.length} >>\nstream\n`), data, Buffer.from('\nendstream')]);
}
const objects = [
  Buffer.from('<< /Type /Catalog /Pages 2 0 R >>'),
  Buffer.from('<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>'),
  Buffer.from('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>'),
  Buffer.from('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
  stream('', Buffer.from('BT /F1 24 Tf 30 100 Td (Harmony PDFKit text 12345) Tj ET')),
  Buffer.from('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1400 260] /Resources << /XObject << /Im1 7 0 R >> >> /Contents 8 0 R >>'),
  stream('/Type /XObject /Subtype /Image /Width 1400 /Height 260 /ColorSpace /DeviceGray /BitsPerComponent 8', pgm.subarray(header.length)),
  stream('', Buffer.from('q 1400 0 0 260 0 0 cm /Im1 Do Q'))
];
const chunks = [Buffer.from('%PDF-1.4\n')];
const offsets = [0];
let size = chunks[0].length;
objects.forEach((object, index) => {
  offsets.push(size);
  const chunk = Buffer.concat([Buffer.from(`${index + 1} 0 obj\n`), object, Buffer.from('\nendobj\n')]);
  chunks.push(chunk); size += chunk.length;
});
chunks.push(Buffer.from(`xref\n0 9\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('')}trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n${size}\n%%EOF\n`));
fs.writeFileSync(path.join(root, 'pdf-fixture.pdf'), Buffer.concat(chunks));
