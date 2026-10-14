"""Static inspection of the isolated signed Stage HAP; never executes an Office engine."""
from pathlib import Path
from io import BytesIO
from datetime import datetime, timezone
import hashlib
import json
import struct
import zipfile

root = Path(__file__).resolve().parents[1]
hap = root / 'tmp/offline-engines/office-stage-probe/entry/build/default/outputs/default/entry-default-signed.hap'
with zipfile.ZipFile(hap) as package:
    assert package.testzip() is None
    names = package.namelist()
    libraries = [name for name in names if name.startswith('libs/')]
    assert libraries and all(name.startswith('libs/arm64-v8a/') for name in libraries)
    records = []
    for name in libraries:
        data = package.read(name)
        assert data[:4] == b'\x7fELF' and data[4] == 2 and struct.unpack_from('<H', data, 18)[0] == 183, name
        records.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    for name in ['liboffice_probe.so', 'libsofficeapp.so', 'libswlo.so', 'libsdlo.so',
                 'libpdffilterlo.so', 'libuno_cppuhelpergcc3.so.3', 'libc++_shared.so']:
        assert 'libs/arm64-v8a/' + name in names
    helper = package.read('libs/arm64-v8a/libuno_cppuhelpergcc3.so.3')
    assert b'LO_OFFICE_PROGRAM_URL' in helper or 'LO_OFFICE_PROGRAM_URL'.encode('utf-16le') in helper
    module = json.loads(package.read('module.json'))
    permissions = module['module'].get('requestPermissions', [])
    assert not any(permission['name'] == 'ohos.permission.INTERNET' for permission in permissions)
    for name in ['layout.docx', 'layout.pptx', 'editable-input.pdf']:
        assert 'resources/rawfile/' + name in names
    with zipfile.ZipFile(BytesIO(package.read('resources/rawfile/office-resources.zip'))) as resources:
        assert resources.testzip() is None
        for name in ['program/unorc', 'program/fundamentalrc', 'program/sofficerc',
                     'program/services.rdb', 'program/types.rdb', 'fonts/DejaVuSans.ttf', 'fonts/DejaVu-LICENSE.txt', 'LICENSE', 'NOTICE']:
            assert name in resources.namelist(), name
        assert any(name.startswith('program/services/') and name.endswith('.rdb') for name in resources.namelist())
        assert any(name.startswith('share/registry/') for name in resources.namelist())
        resource_bytes = sum(item.file_size for item in resources.infolist())
report = {'scope': 'Office isolated HAP static packaging only', 'checkedAtUtc': datetime.now(timezone.utc).isoformat(),
          'result': 'passed', 'hapBytes': hap.stat().st_size, 'hapSha256': hashlib.sha256(hap.read_bytes()).hexdigest(),
          'nativeLibraryCount': len(records), 'allNativeLibraries': 'ELF64 AArch64',
          'unoResourcePathPatchPackaged': True, 'offlineResourcesUncompressedBytes': resource_bytes,
          'internetPermissionDeclared': False, 'libraries': records,
          'engineInitializationAfterPatch': 'pending device', 'docxToPdf': 'pending device',
          'pptxToPdf': 'pending device', 'pdfToEditableOffice': 'not integrated',
          'mainApplicationRouteAvailability': 'unchanged'}
(root / 'tests/generated/office-stage-package-validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({key: value for key, value in report.items() if key != 'libraries'}, indent=2))
