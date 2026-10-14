"""Independent JPEG metadata acceptance and PDF rendering regression; no user files are bundled."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import subprocess
import re

from PIL import Image, ImageCms, ImageChops, ImageOps, ImageStat
from pypdf import PdfReader

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('cli', type=Path)
parser.add_argument('--user-image', type=Path)
parser.add_argument('--device-log', type=Path)
args = parser.parse_args()
directory = root / 'tmp/pdfs/jpeg-metadata'
directory.mkdir(parents=True, exist_ok=True)
poppler = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin/pdftoppm.exe'
profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
image = Image.new('RGB', (96, 64))
for y in range(image.height):
    for x in range(image.width):
        image.putpixel((x, y), ((x * 2 + 30) % 256, (y * 3 + 20) % 256, 40 if x < 40 else 210))
cases = []

def verify(source, output, name):
    pdf = PdfReader(output, strict=True)
    assert len(pdf.pages) == 1 and not pdf.is_encrypted
    page = pdf.pages[0]
    objects = list(page['/Resources']['/XObject'].get_object().values())
    assert len(objects) == 1
    jpeg = objects[0].get_object()
    assert jpeg['/Filter'] == '/DCTDecode' and jpeg.get_data() == source.read_bytes()
    original = Image.open(source)
    icc = original.info.get('icc_profile', b'')
    if icc:
        assert jpeg['/ColorSpace'][0] == '/ICCBased'
        embedded = jpeg['/ColorSpace'][1].get_object()
        assert embedded['/N'] == 3 and embedded.get_data() == icc
    reference = ImageOps.exif_transpose(original).convert('RGB')
    if icc:
        reference = ImageCms.profileToProfile(reference, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
            ImageCms.createProfile('sRGB'), renderingIntent=int.from_bytes(icc[64:68], 'big'), outputMode='RGB')
    exif = original.getexif()
    dpi_x, dpi_y = (72, 72)
    if exif.get(282) and exif.get(283) and exif.get(296, 2) != 1:
        factor = 2.54 if exif.get(296, 2) == 3 else 1
        dpi_x, dpi_y = float(exif[282]) * factor, float(exif[283]) * factor
    if exif.get(274, 1) >= 5:
        dpi_x, dpi_y = dpi_y, dpi_x
    assert abs(float(page.mediabox.width) - reference.width * 72 / dpi_x) < 0.001
    assert abs(float(page.mediabox.height) - reference.height * 72 / dpi_y) < 0.001
    prefix = directory / (name + '-rendered')
    subprocess.run([str(poppler), '-r', '72', '-scale-to-x', str(reference.width), '-scale-to-y',
                    str(reference.height), '-singlefile', '-png', str(output), str(prefix)],
        check=True, capture_output=True)
    rendered = Image.open(str(prefix) + '.png').convert('RGB')
    assert rendered.size == reference.size
    difference = sum(ImageStat.Stat(ImageChops.difference(rendered, reference)).mean) / 3
    assert difference < 6.0, (name, difference)
    return {'name': name, 'result': 'passed', 'jpegPayloadIdentical': True,
            'iccBytesPreserved': len(icc), 'orientation': original.getexif().get(274, 1),
            'renderedSize': list(rendered.size), 'meanAbsoluteRenderedDifference': difference}

def convert(name, data, expected=None):
    source = directory / (name + '.jpg')
    output = directory / (name + '.pdf')
    source.write_bytes(data)
    if output.exists():
        output.unlink()  # Exact test artifact owned by this script.
    process = subprocess.run([str(args.cli.resolve()), str(source), str(output)],
        capture_output=True, text=True, timeout=60)
    if expected:
        assert process.returncode != 0 and not output.exists(), (name, process.stdout)
        assert json.loads(process.stderr)['code'] == expected, (name, process.stderr)
        cases.append({'name': name, 'result': 'passed', 'expectedRejection': expected})
    else:
        assert process.returncode == 0, (name, process.stderr)
        cases.append(verify(source, output, name))

def jpeg(orientation=1, icc=None):
    exif = Image.Exif()
    exif[274] = orientation
    stream = io.BytesIO()
    image.save(stream, 'JPEG', quality=95, subsampling=0, dpi=(72, 72), exif=exif, icc_profile=icc)
    return stream.getvalue()

for orientation in range(1, 9):
    convert('exif-orientation-' + str(orientation), jpeg(orientation))
convert('icc', jpeg(1, profile))
convert('icc-exif-6', jpeg(6, profile))
convert('exif-invalid-orientation', jpeg(9), 'FILE_CORRUPTED')
bad_profile = bytearray(profile)
bad_profile[36:40] = b'xxxx'
convert('icc-invalid-signature', jpeg(1, bytes(bad_profile)), 'FILE_CORRUPTED')
bad_profile = bytearray(profile)
bad_profile[16:20] = b'CMYK'
convert('icc-color-mismatch', jpeg(1, bytes(bad_profile)), 'UNSUPPORTED_FEATURE')
convert('icc-truncated', jpeg(1, profile[:-8]), 'FILE_CORRUPTED')
unknown = b'\xff\xe3\x00\x08opaque'
baseline = jpeg()
convert('unknown-app-segment', baseline[:2] + unknown + baseline[2:], 'UNSUPPORTED_FEATURE')

def app(marker, payload):
    return bytes([255, marker]) + (len(payload) + 2).to_bytes(2, 'big') + payload

plain = io.BytesIO()
image.save(plain, 'JPEG', quality=95, subsampling=0, dpi=(72, 72))
plain = plain.getvalue()
def prepend(*segments):
    return plain[:2] + b''.join(segments) + plain[2:]

half = len(profile) // 2
first = app(226, b'ICC_PROFILE\0\1\2' + profile[:half])
second = app(226, b'ICC_PROFILE\0\2\2' + profile[half:])
convert('icc-reordered-chunks', prepend(second, first))
convert('icc-missing-chunk', prepend(first), 'FILE_CORRUPTED')
convert('icc-duplicate-chunk', prepend(first, first, second), 'FILE_CORRUPTED')
convert('icc-zero-chunk', prepend(app(226, b'ICC_PROFILE\0\0\1' + profile)), 'FILE_CORRUPTED')
bad_table = bytearray(profile)
bad_table[136:140] = (0x7fffffff).to_bytes(4, 'big')
convert('icc-tag-out-of-bounds', prepend(app(226, b'ICC_PROFILE\0\1\1' + bad_table)), 'FILE_CORRUPTED')
little = b'Exif\0\0II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0\x06\0\0\0\0\0\0\0'
convert('exif-little-endian-6', prepend(app(225, little)))
bad_exif = bytearray(little)
bad_exif[10:14] = (0x7fffffff).to_bytes(4, 'little')
convert('exif-offset-out-of-bounds', prepend(app(225, bad_exif)), 'FILE_CORRUPTED')
convert('exif-duplicate', prepend(app(225, little), app(225, little)), 'FILE_CORRUPTED')
convert('xmp-not-supported', prepend(app(225, b'http://ns.adobe.com/xap/1.0/\0<xml/>')), 'UNSUPPORTED_FEATURE')
convert('late-exif-not-ignored', plain[:-2] + app(225, little) + plain[-2:], 'UNSUPPORTED_FEATURE')
density = Image.Exif()
density[274], density[282], density[283], density[296] = 6, 96, 96, 2
density_jpeg = io.BytesIO()
image.save(density_jpeg, 'JPEG', quality=95, subsampling=0, dpi=(72, 72), exif=density)
convert('exif-physical-density', density_jpeg.getvalue())
for color, icc, expected in [(1, None, None), (65535, None, 'UNSUPPORTED_FEATURE'), (65535, profile, None)]:
    tagged = Image.Exif()
    tagged[34665] = {40961: color}
    tagged_jpeg = io.BytesIO()
    image.save(tagged_jpeg, 'JPEG', quality=95, subsampling=0, dpi=(72, 72), exif=tagged, icc_profile=icc)
    convert('exif-color-' + str(color) + ('-icc' if icc else ''), tagged_jpeg.getvalue(), expected)
if args.user_image:
    # Keep the supplied file read-only and the output local; reports do not expose its path or contents.
    source = args.user_image.resolve()
    output = root / 'output/pdf/jpeg-user-check.pdf'
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    process = subprocess.run([str(args.cli.resolve()), str(source), str(output)],
        capture_output=True, text=True, timeout=60)
    assert process.returncode == 0, process.stderr
    cases.append(verify(source, output, 'supplied-image'))
device = None
if args.device_log:
    chunks = re.findall(r'METADATA_PDF_SHA256=([a-f0-9]{64}) PART=(\d+)/(\d+) BASE64=([A-Za-z0-9+/=]+)',
                        args.device_log.read_text(encoding='utf-8-sig'))
    assert chunks, 'No metadata PDF captured from device'
    sha256, _, total, _ = chunks[-1]
    parts = {int(part): value for digest, part, count, value in chunks if digest == sha256 and count == total}
    assert set(parts) == set(range(1, int(total) + 1))
    data = base64.b64decode(''.join(parts[i] for i in sorted(parts)), validate=True)
    assert hashlib.sha256(data).hexdigest() == sha256
    output = directory / 'device-metadata.pdf'
    output.write_bytes(data)
    device = verify(root / 'entry/src/ohosTest/resources/rawfile/jpeg-debug-exif-icc.jpg', output, 'device-metadata')
    device['pdfSha256'] = sha256
report = {'scope': 'native_converter_independent_PDF_parse_and_render', 'hostPassed': len(cases),
          'cases': cases, 'actualDeviceMetadataPdf': device}
(root / 'tests/generated/jpeg-metadata-host-report.json').write_text(
    json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'hostPassed': len(cases), 'suppliedImageTested': args.user_image is not None,
                  'devicePdfVerified': device is not None}))
