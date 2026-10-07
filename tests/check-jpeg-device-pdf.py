import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader

root = Path(__file__).resolve().parent.parent
log = (root / 'tmp/jpeg-sync-smoke-hilog.log').read_text(encoding='utf-8-sig')
matches = re.findall(r'PDF_SHA256=([a-f0-9]{64}) PDF_BASE64=([A-Za-z0-9+/=]+)', log)
assert matches, 'No device-generated PDF captured'
expected_hash, encoded = matches[-1]
pdf_bytes = base64.b64decode(encoded, validate=True)
assert hashlib.sha256(pdf_bytes).hexdigest() == expected_hash, 'Native/export digest mismatch'
directory = root / 'tmp/pdfs/jpeg-device-smoke'
directory.mkdir(parents=True, exist_ok=True)
pdf = directory / 'baseline-device-output.pdf'
pdf.write_bytes(pdf_bytes)
fixture = root / 'entry/src/main/cpp/tests/fixtures/baseline.jpg'
reader = PdfReader(pdf, strict=True)
assert not reader.is_encrypted and len(reader.pages) == 1
page = reader.pages[0]
images = list(page['/Resources']['/XObject'].get_object().values())
assert len(images) == 1
image = images[0].get_object()
assert image['/Subtype'] == '/Image' and image['/Filter'] == '/DCTDecode'
assert image.get_data() == fixture.read_bytes(), 'JPEG payload changed'
source = Image.open(fixture)
assert (image['/Width'], image['/Height']) == source.size
poppler = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin/pdftoppm.exe'
subprocess.run([str(poppler), '-r', '72', '-singlefile', '-png', str(pdf), str(directory / 'rendered')], check=True)
rendered = Image.open(directory / 'rendered.png')
assert rendered.size == source.size
difference = ImageChops.difference(rendered.convert('RGB'), source.convert('RGB'))
mean_difference = sum(ImageStat.Stat(difference).mean) / 3
assert mean_difference < 6.0, 'Rendered pixel difference exceeds the existing JPEG regression threshold'
report = {
    'scope': 'independent_parse_and_render_of_synthetic_JPEG_PDF_created_on_device',
    'result': 'passed', 'pdfSha256': expected_hash, 'pdfBytes': len(pdf_bytes),
    'pageCount': len(reader.pages), 'pageSizePt': [float(page.mediabox.width), float(page.mediabox.height)],
    'imageSizePixels': list(source.size), 'jpegPayloadByteIdentical': True,
    'renderDpi': 72, 'renderSizeMatchesSource': True,
    'meanAbsoluteRenderedDifference': mean_difference,
    'systemPickerSaveShareAndUserDocuments': 'not_tested'
}
(root / 'tests/generated/jpeg-local-sync-pdf-validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps(report, indent=2))
