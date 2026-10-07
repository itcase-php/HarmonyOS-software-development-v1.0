// Bounded, editable OOXML packages from measured page objects. No page screenshots.
export interface OfficeText {
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
  font: string;
  size: number;
  color: string;
}
export interface OfficeImage {
  png: Uint8Array;
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface OfficePage { width: number; height: number; texts: OfficeText[]; images: OfficeImage[]; }
interface PackageEntry { path: string; bytes: Uint8Array; }

const MAX_BYTES: number = 16 * 1024 * 1024;
const W: string = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const A: string = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const P: string = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const R: string = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const REL: string = 'http://schemas.openxmlformats.org/package/2006/relationships';

function xml(value: string): string {
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)) { throw new Error('OFFICE_XML_CONTROL'); }
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}
function utf8(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let index: number = 0; index < value.length; index++) {
    let code: number = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      const low: number = value.charCodeAt(++index);
      if (low < 0xdc00 || low > 0xdfff || !Number.isFinite(low)) { throw new Error('OFFICE_INVALID_UNICODE'); }
      code = 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00;
    } else if (code >= 0xdc00 && code <= 0xdfff) { throw new Error('OFFICE_INVALID_UNICODE'); }
    if (code < 0x80) { bytes.push(code); }
    else if (code < 0x800) { bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63)); }
    else if (code < 0x10000) { bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)); }
    else { bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)); }
  }
  return new Uint8Array(bytes);
}
function relationships(contents: string): string { return `<Relationships xmlns="${REL}">${contents}</Relationships>`; }
function relation(id: string, type: string, target: string): string {
  return `<Relationship Id="${id}" Type="${R}/${type}" Target="${target}"/>`;
}
function crc32(bytes: Uint8Array): number {
  let crc: number = 0xffffffff;
  for (const value of bytes) {
    crc ^= value;
    for (let bit: number = 0; bit < 8; bit++) { crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function zip(entries: PackageEntry[]): Uint8Array {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset: number = 0;
  for (const entry of entries) {
    const name: Uint8Array = utf8(entry.path);
    const crc: number = crc32(entry.bytes);
    const local: Uint8Array = new Uint8Array(30 + name.length);
    const view: DataView = new DataView(local.buffer);
    view.setUint32(0, 0x04034b50, true); view.setUint16(4, 20, true);
    view.setUint16(6, 0x800, true); view.setUint32(14, crc, true);
    view.setUint32(18, entry.bytes.length, true); view.setUint32(22, entry.bytes.length, true);
    view.setUint16(26, name.length, true); local.set(name, 30);
    const directory: Uint8Array = new Uint8Array(46 + name.length);
    const record: DataView = new DataView(directory.buffer);
    record.setUint32(0, 0x02014b50, true); record.setUint16(4, 20, true); record.setUint16(6, 20, true);
    record.setUint16(8, 0x800, true); record.setUint32(16, crc, true);
    record.setUint32(20, entry.bytes.length, true); record.setUint32(24, entry.bytes.length, true);
    record.setUint16(28, name.length, true); record.setUint32(42, offset, true); directory.set(name, 46);
    parts.push(local, entry.bytes); central.push(directory); offset += local.length + entry.bytes.length;
    if (offset > MAX_BYTES) { throw new Error('OFFICE_PACKAGE_LIMIT'); }
  }
  let centralSize: number = 0;
  for (const record of central) { centralSize += record.length; }
  if (offset + centralSize + 22 > MAX_BYTES) { throw new Error('OFFICE_PACKAGE_LIMIT'); }
  const end: Uint8Array = new Uint8Array(22);
  const view: DataView = new DataView(end.buffer);
  view.setUint32(0, 0x06054b50, true); view.setUint16(8, entries.length, true); view.setUint16(10, entries.length, true);
  view.setUint32(12, centralSize, true); view.setUint32(16, offset, true);
  const result: Uint8Array = new Uint8Array(offset + centralSize + end.length);
  let position: number = 0;
  for (const part of parts.concat(central).concat([end])) { result.set(part, position); position += part.length; }
  return result;
}
function check(pages: OfficePage[]): void {
  if (pages.length === 0 || pages.length > 100) { throw new Error('OFFICE_PAGE_LIMIT'); }
  let objects: number = 0;
  let bytes: number = 0;
  for (const page of pages) {
    if (![page.width, page.height].every((n: number) => Number.isFinite(n) && n > 0 && n <= 14400)) {
      throw new Error('OFFICE_PAGE_SIZE');
    }
    objects += page.texts.length + page.images.length;
    for (const object of page.texts) {
      if (object.text.length > 65536 || object.font.length === 0 || object.font.length > 128 ||
        !/^[a-fA-F0-9]{6}$/.test(object.color) || !Number.isFinite(object.size) || object.size <= 0 || object.size > 400) {
        throw new Error('OFFICE_TEXT_INVALID');
      }
      bytes += object.text.length * 4;
      xml(object.text); xml(object.font);
      if (![object.x, object.y, object.width, object.height].every((n: number) => Number.isFinite(n) && n >= 0 && n <= 14400) ||
        object.width === 0 || object.height === 0) { throw new Error('OFFICE_OBJECT_BOUNDS'); }
    }
    for (const object of page.images) {
      if (![object.x, object.y, object.width, object.height].every((n: number) => Number.isFinite(n) && n >= 0 && n <= 14400) ||
        object.width === 0 || object.height === 0 || object.png.length < 24 ||
        ![137, 80, 78, 71, 13, 10, 26, 10].every((n: number, index: number) => object.png[index] === n)) {
        throw new Error('OFFICE_IMAGE_INVALID');
      }
      bytes += object.png.length;
    }
  }
  if (objects > 5000 || bytes > MAX_BYTES / 2) { throw new Error('OFFICE_CONTENT_LIMIT'); }
}

export class OfficePackageWriter {
  static docx(pages: OfficePage[]): Uint8Array {
    check(pages);
    const entries: PackageEntry[] = [];
    const add = (path: string, content: string): void => { entries.push({ path, bytes: utf8(content) }); };
    const contentType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
    add('[Content_Types].xml', `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="${contentType}"/></Types>`);
    add('_rels/.rels', relationships(relation('rId1', 'officeDocument', 'word/document.xml')));
    let body: string = '';
    let rels: string = '';
    let id: number = 0;
    for (let index: number = 0; index < pages.length; index++) {
      const page = pages[index];
      let shapes: string = '';
      for (const text of page.texts) {
        const style = `position:absolute;margin-left:${text.x}pt;margin-top:${text.y}pt;width:${text.width}pt;height:${text.height}pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page`;
        shapes += `<w:r><w:pict><v:shape id="text${++id}" style="${style}" stroked="f" filled="f"><v:textbox inset="0,0,0,0"><w:txbxContent><w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="${xml(text.font)}" w:hAnsi="${xml(text.font)}" w:eastAsia="${xml(text.font)}"/><w:color w:val="${text.color}"/><w:sz w:val="${Math.round(text.size * 2)}"/></w:rPr><w:t xml:space="preserve">${xml(text.text).replace(/\r\n?|\n/g, '</w:t><w:br/><w:t xml:space="preserve">')}</w:t></w:r></w:p></w:txbxContent></v:textbox></v:shape></w:pict></w:r>`;
      }
      for (const image of page.images) {
        const key: string = `image${++id}`;
        entries.push({ path: `word/media/${key}.png`, bytes: image.png });
        rels += relation(key, 'image', `media/${key}.png`);
        shapes += `<w:r><w:pict><v:shape id="${key}" style="position:absolute;margin-left:${image.x}pt;margin-top:${image.y}pt;width:${image.width}pt;height:${image.height}pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page" stroked="f"><v:imagedata r:id="${key}"/></v:shape></w:pict></w:r>`;
      }
      const section = `<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="${Math.round(page.width * 20)}" w:h="${Math.round(page.height * 20)}"/><w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>`;
      body += `<w:p>${shapes}</w:p>`;
      body += index + 1 < pages.length ? `<w:p><w:pPr>${section}</w:pPr></w:p>` : section;
    }
    add('word/document.xml', `<w:document xmlns:w="${W}" xmlns:r="${R}" xmlns:v="urn:schemas-microsoft-com:vml"><w:body>${body}</w:body></w:document>`);
    add('word/_rels/document.xml.rels', relationships(rels));
    return zip(entries);
  }

  static pptx(pages: OfficePage[]): Uint8Array {
    check(pages);
    if (!pages.every((page: OfficePage) => page.width === pages[0].width && page.height === pages[0].height)) {
      throw new Error('OFFICE_MIXED_SLIDE_SIZES');
    }
    const entries: PackageEntry[] = [];
    const add = (path: string, content: string): void => { entries.push({ path, bytes: utf8(content) }); };
    const group: string = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>';
    let types: string = '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>';
    types += '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>';
    types += '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>';
    let slides: string = '';
    let rels: string = relation('master', 'slideMaster', 'slideMasters/slideMaster1.xml');
    for (let index: number = 0; index < pages.length; index++) {
      const page = pages[index];
      const number: number = index + 1;
      types += `<Override PartName="/ppt/slides/slide${number}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`;
      slides += `<p:sldId id="${256 + index}" r:id="slide${number}"/>`;
      rels += relation(`slide${number}`, 'slide', `slides/slide${number}.xml`);
      let content: string = group;
      let slideRels: string = relation('layout', 'slideLayout', '../slideLayouts/slideLayout1.xml');
      let id: number = 1;
      for (const text of page.texts) {
        const properties = `<a:rPr sz="${Math.round(text.size * 100)}"><a:solidFill><a:srgbClr val="${text.color}"/></a:solidFill><a:latin typeface="${xml(text.font)}"/><a:ea typeface="${xml(text.font)}"/></a:rPr>`;
        const runs = text.text.split(/\r\n?|\n/).map((line: string) =>
          `<a:r>${properties}<a:t>${xml(line)}</a:t></a:r>`).join('<a:br/>');
        content += `<p:sp><p:nvSpPr><p:cNvPr id="${++id}" name="Text ${id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${Math.round(text.x * 12700)}" y="${Math.round(text.y * 12700)}"/><a:ext cx="${Math.round(text.width * 12700)}" cy="${Math.round(text.height * 12700)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0"/><a:lstStyle/><a:p><a:pPr><a:spcBef><a:spcPts val="0"/></a:spcBef><a:spcAft><a:spcPts val="0"/></a:spcAft></a:pPr>${runs}</a:p></p:txBody></p:sp>`;
      }
      for (const image of page.images) {
        const key: string = `image${number}_${++id}`;
        entries.push({ path: `ppt/media/${key}.png`, bytes: image.png });
        slideRels += relation(key, 'image', `../media/${key}.png`);
        content += `<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="Image ${id}"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="${key}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="${Math.round(image.x * 12700)}" y="${Math.round(image.y * 12700)}"/><a:ext cx="${Math.round(image.width * 12700)}" cy="${Math.round(image.height * 12700)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>`;
      }
      add(`ppt/slides/slide${number}.xml`, `<p:sld xmlns:p="${P}" xmlns:a="${A}" xmlns:r="${R}"><p:cSld><p:spTree>${content}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>`);
      add(`ppt/slides/_rels/slide${number}.xml.rels`, relationships(slideRels));
    }
    add('[Content_Types].xml', `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">${types}</Types>`);
    add('_rels/.rels', relationships(relation('rId1', 'officeDocument', 'ppt/presentation.xml')));
    add('ppt/presentation.xml', `<p:presentation xmlns:p="${P}" xmlns:r="${R}"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="master"/></p:sldMasterIdLst><p:sldIdLst>${slides}</p:sldIdLst><p:sldSz cx="${Math.round(pages[0].width * 12700)}" cy="${Math.round(pages[0].height * 12700)}"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>`);
    add('ppt/_rels/presentation.xml.rels', relationships(rels));
    add('ppt/slideMasters/slideMaster1.xml', `<p:sldMaster xmlns:p="${P}" xmlns:a="${A}" xmlns:r="${R}"><p:cSld><p:spTree>${group}</p:spTree></p:cSld><p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="layout"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>`);
    add('ppt/slideMasters/_rels/slideMaster1.xml.rels', relationships(relation('layout', 'slideLayout', '../slideLayouts/slideLayout1.xml')));
    add('ppt/slideLayouts/slideLayout1.xml', `<p:sldLayout xmlns:p="${P}" xmlns:a="${A}" type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>${group}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`);
    add('ppt/slideLayouts/_rels/slideLayout1.xml.rels', relationships(relation('master', 'slideMaster', '../slideMasters/slideMaster1.xml')));
    return zip(entries);
  }
}
