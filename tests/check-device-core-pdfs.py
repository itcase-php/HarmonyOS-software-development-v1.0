"""Verify captured repository PDFs from a real device; never infer engine execution from host mocks."""
import argparse, base64, hashlib, json, re, subprocess
from pathlib import Path
from PIL import Image, ImageChops
from pypdf import PdfReader

repository = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('log',type=Path)
parser.add_argument('--output',type=Path,default=repository/'tmp/core-engines/device-pdfs')
parser.add_argument('--report',type=Path,default=repository/'tests/generated/core-device-pdfs.json')
parser.add_argument('--allow-partial',action='store_true')
args = parser.parse_args()
log = args.log.read_text(encoding='utf-8-sig')
starts = [line for line in log.splitlines() if any(marker in line for marker in
          ['CORE_START ', 'CORE_OK ', 'SAVED_PDF_SELECT_START', 'SAVED_PDF_READBACK_OK'])]
assert starts, 'No device cases started'
pid = starts[-1].split()[2]
lines = '\n'.join(line for line in log.splitlines() if len(line.split()) > 2 and line.split()[2] == pid)
parts = {}
for label, digest, part, total, data in re.findall(r'CORE_PDF format=([\w-]+) sha256=(\w+) part=(\d+)/(\d+) data=([A-Za-z0-9+/=]+)', lines):
    parts.setdefault((label, digest, int(total)), {})[int(part)] = data
outputs = args.output
outputs.mkdir(parents=True,exist_ok=True)
poppler = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin/pdftoppm.exe'
checks = []
for label, digest, total in parts:
    chunks = parts[(label, digest, total)]
    assert set(chunks) == set(range(1, total+1)), (label, len(chunks), total)
    data = base64.b64decode(''.join(chunks[n] for n in range(1,total+1)), validate=True)
    assert hashlib.sha256(data).hexdigest() == digest
    path = outputs/(label+'.pdf')
    path.write_bytes(data)
    document = PdfReader(path, strict=True)
    text = '\n'.join(page.extract_text() or '' for page in document.pages)
    expected = {'docx':(2,[612,792],['Harmony Office Conversion','678.90','Second Page','98765','Alpha','Beta','123.45','555.45']),
                'pptx':(2,[960,540],['Harmony Presentation','Editable Objects','12345','678.90']),
                'png':(1,None,[]),
                'docx-cjk':(1,[612,792],['鸿蒙离线文档转换','678.90','12345','中文表格','98765','✓','→','©']),
                'pptx-cjk':(1,[960,540],['鸿蒙离线文档转换','678.90','12345','✓','→','©']),
                'docx-default':(1,[612,792],['Bundled font default policy','12345']),
                'docx-font-approved':(1,[612,792],['Explicit fallback sample','12345']),
                'docx-common-fonts':(1,[595.276,841.89],['宋体与黑体转换测试','鸿蒙离线字体验证','自有测试文件，仅用于转换、保存与分享验证','678.90','12345','服务 A','服务 B','123.45','555.45','98765','✓','→','©'])}.get(label)
    if label == 'saved-docx':
        expected = (2,[612,792],['Harmony Office Conversion','678.90','Second Page','98765','Alpha','Beta','123.45','555.45'])
    if label == 'saved-docx-common-fonts':
        expected = (1,[595.276,841.89],['宋体与黑体转换测试','鸿蒙离线字体验证','自有测试文件，仅用于转换、保存与分享验证','678.90','12345','服务 A','服务 B','123.45','555.45','98765','✓','→','©'])
    if label == 'saved-pptx':
        expected = (2,[960,540],['Harmony Presentation','Editable Objects','12345','678.90'])
    if label in {'saved-png', 'saved-jpeg'}:
        expected = (1,None,[])
    assert expected, 'Unexpected fixture label: ' + label
    if expected:
        assert len(document.pages) == expected[0], (label, len(document.pages))
        for token in expected[2]: assert token in text, (label, token, text)
        if expected[1]:
            for page in document.pages:
                assert abs(float(page.mediabox.width)-expected[1][0]) < .1
                assert abs(float(page.mediabox.height)-expected[1][1]) < .1
    if label not in {'png','docx-default','docx-font-approved'}: assert len(document.pages[0].images) >= 1
    if label in {'png', 'saved-png'}:
        original = Image.open(repository/'entry/src/ohosTest/resources/rawfile/core-layout.png').convert('RGB')
        embedded = document.pages[0].images[0].image.convert('RGB')
        assert original.size == embedded.size and ImageChops.difference(original, embedded).getbbox() is None, label
    if label == 'saved-jpeg':
        image = list(document.pages[0]['/Resources']['/XObject'].get_object().values())[0].get_object()
        assert image['/Filter'] == '/DCTDecode'
        assert image.get_data() == (repository/'entry/src/ohosTest/resources/rawfile/jpeg-debug-exif-icc.jpg').read_bytes()
    images = []
    fonts = []
    for index, page in enumerate(document.pages):
        images.append(len(page.images))
        font_map = page.get('/Resources',{}).get('/Font',{})
        if hasattr(font_map,'get_object'): font_map = font_map.get_object()
        for font in font_map.values():
            f = font.get_object()
            fonts.append(str(f.get('/BaseFont','')))
    subprocess.run([str(poppler),'-png','-r','110',str(path),str(outputs/label)],check=True,capture_output=True)
    checks.append({'label':label,'bytes':len(data),'sha256':digest,'pages':len(document.pages),
                   'imageResourcesPerPage':images,'fonts':sorted(set(fonts)),'text':text,
                   'independentParse':'passed','rendered':'passed','visualInspection':'not assessed by script'})
assert checks, 'No complete PDF captures'
labels = {item['label'] for item in checks}
expected_labels = {'docx','pptx','png'} | ({'docx-cjk','pptx-cjk'} if 'format=docx-cjk' in lines else set())
if 'CORE_START format=docx-default' in lines: expected_labels |= {'docx-default','docx-font-approved'}
if 'CORE_START format=docx-common-fonts' in lines: expected_labels.add('docx-common-fonts')
if 'SAVED_PDF_SELECT_START' in lines or 'SAVED_PDF_READBACK_OK' in lines:
    assert len(labels) == 1 and next(iter(labels)).startswith('saved-'), labels
    expected_labels = labels
if not args.allow_partial: assert labels == expected_labels, (labels, expected_labels)
args.report.write_text(json.dumps({'scope':'actual device fixture PDFs, hash-checked capture, independent pypdf and Poppler',
                                  'checks':checks},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps([{k:v for k,v in record.items() if k!='text'} for record in checks],ensure_ascii=True))
