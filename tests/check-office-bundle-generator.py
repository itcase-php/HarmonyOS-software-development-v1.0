"""Run the real packager against synthetic inputs; no usable engine or font is mocked as real."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys, tempfile, zipfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='office-bundle-generator-') as directory:
    project = Path(directory)
    (project / 'tools').mkdir()
    script = project / 'tools/package-office-main.py'
    shutil.copyfile(root / 'tools/package-office-main.py', script)
    for path in ['entry/src/main/cpp/generated', 'entry/src/main/ets/generated']:
        (project / path).mkdir(parents=True)
    stage = project / 'stage'
    libraries = stage / 'libs/arm64-v8a'
    libraries.mkdir(parents=True)
    # Only the packager's ELF header check is exercised, never dynamic loading.
    header = bytearray(20)
    header[:6] = b'\x7fELF\x02\x01'
    header[18:20] = (183).to_bytes(2, 'little')
    (libraries / 'libsofficeapp.so').write_bytes(header)
    headers = stage / 'src/main/cpp/include/LibreOfficeKit'
    headers.mkdir(parents=True)
    (headers / 'test.h').write_text('// synthetic packager test\n', encoding='utf8')
    resources = stage / 'src/main/resources/rawfile'
    resources.mkdir(parents=True)
    with zipfile.ZipFile(resources / 'office-resources.zip', 'w') as archive:
        for name in ['program/fundamentalrc', 'program/unorc', 'fonts/DejaVuSans.ttf',
                     'presets/basic/script.xlc', 'LICENSE', 'NOTICE']:
            archive.writestr(name, b'synthetic packager input, not a real font or engine\n')
    subprocess.run([sys.executable, str(script), '--stage', str(stage)], check=True, capture_output=True)
    manifest = (project / 'shared/engines/office-bundle.json').read_bytes()
    expected = hashlib.sha256(manifest).hexdigest()
    actual = (project / 'entry/src/main/resources/rawfile/office/manifest.json').read_bytes()
    assert actual == manifest
    for path in ['entry/src/main/ets/generated/OfficeBundle.ets', 'entry/src/main/cpp/generated/office_bundle.h']:
        assert expected in (project / path).read_text(), 'Generated digest does not match bytes on disk: ' + path
    assert b'\r\n' not in manifest, 'Manifest must use deterministic LF bytes on every host'
    parsed = json.loads(manifest)
    assert len(parsed['resources']) == 6 and len(parsed['libraries']) == 1
    with zipfile.ZipFile(resources / 'office-resources.zip', 'w') as archive:
        for name in ['program/fundamentalrc', 'program/unorc', 'fonts/DejaVuSans.ttf', 'LICENSE', 'NOTICE']:
            archive.writestr(name, b'synthetic packager input')
    rejected = subprocess.run([sys.executable, str(script), '--stage', str(stage)], capture_output=True, text=True)
    assert rejected.returncode != 0 and 'presets/basic/script.xlc' in rejected.stderr
    print(json.dumps({'result': 'passed', 'scope': 'real packager with synthetic files; no engine execution',
                      'manifestDigestMatchesWrittenBytes': True, 'deterministicLf': True,
                      'missingProfilePresetsRejected': True}))
