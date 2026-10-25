"""Inspect the final main HAP. Static packaging evidence, never device execution."""
from pathlib import Path
from io import BytesIO
from datetime import datetime, timezone
import hashlib
import json
import struct
import zipfile
import argparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--build-mode', choices=['debug', 'release'], default='debug')
parser.add_argument('--hap', type=Path, default=root / 'entry/build/default/outputs/default/entry-default-signed.hap')
parser.add_argument('--test-hap', type=Path, help='Also verify the paired test module and its owned fixtures')
args = parser.parse_args()
hap = args.hap.resolve()
profile = (root / 'entry/build/default/generated/profile/default/BuildProfile.ets').read_text(encoding='utf8')
assert "BUILD_MODE_NAME = '" + args.build_mode + "'" in profile
assert 'DEBUG = ' + ('true' if args.build_mode == 'debug' else 'false') in profile
sdk = Path('D:/DevEco Studio2026/DevEco Studio/sdk/default/openharmony/native')
manifest_bytes = (root / 'shared/engines/office-bundle.json').read_bytes()
manifest = json.loads(manifest_bytes)
sha = lambda data: hashlib.sha256(data).hexdigest()
for stamp in ['entry/src/main/cpp/generated/office_bundle.h', 'entry/src/main/ets/generated/OfficeBundle.ets']:
    assert '"' + sha(manifest_bytes) + '"' in (root / stamp).read_text(encoding='utf8'), 'Office manifest stamp mismatch: ' + stamp

def elf(data):
    assert data[:6] == b'\x7fELF\x02\x01'
    machine = struct.unpack_from('<H', data, 18)[0]
    section_start = struct.unpack_from('<Q', data, 40)[0]
    entry_size, section_count = struct.unpack_from('<HH', data, 58)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, section_start + index * entry_size)
                for index in range(section_count)]
    needed, exports, imports, functions = [], set(), set(), set()
    for section in sections:
        kind, offset, size, link, stride = section[1], section[4], section[5], section[6], section[9]
        if kind not in (2, 6, 11):
            continue
        strings_section = sections[link]
        strings = data[strings_section[4]:strings_section[4] + strings_section[5]]
        for position in range(offset, offset + size, stride):
            if kind == 6:
                tag, value = struct.unpack_from('<QQ', data, position)
                if tag == 1:
                    needed.append(strings[value:strings.index(b'\0', value)].decode())
            else:
                name, info, other, defined, value, length = struct.unpack_from('<IBBHQQ', data, position)
                if defined and info & 15 == 2:
                    functions.add(strings[name:strings.index(b'\0', name)].decode())
                if kind == 2:
                    continue
                if defined and info >> 4 in (1, 2) and other & 3 in (0, 3):
                    exports.add(strings[name:strings.index(b'\0', name)].decode())
                elif not defined and info >> 4 == 1:
                    imports.add(strings[name:strings.index(b'\0', name)].decode())
    return machine, needed, exports, imports, functions

def allocated_sections(data):
    start = struct.unpack_from('<Q', data, 40)[0]
    stride, count, names_index = struct.unpack_from('<HHH', data, 58)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, start + index * stride) for index in range(count)]
    names = sections[names_index]
    strings = data[names[4]:names[4] + names[5]]
    return [(strings[section[0]:strings.index(b'\0', section[0])].decode(), section[2], section[3], section[5],
             sha(data[section[4]:section[4] + section[5]]) if section[1] != 8 else '')
            for section in sections if section[2] & 2]

records = []
with zipfile.ZipFile(hap) as package:
    assert package.testzip() is None
    names = set(package.namelist())
    expected = {'libs/arm64-v8a/' + entry['name'] for entry in manifest['libraries']}
    assert expected <= names
    for entry in manifest['libraries']:
        data = package.read('libs/arm64-v8a/' + entry['name'])
        original = (root / 'entry/libs/arm64-v8a' / entry['name']).read_bytes()
        assert len(original) == entry['byteSize'] and sha(original) == entry['sha256'], 'Office source library differs from manifest: ' + entry['name']
        # Hvigor strips non-loaded symbols; all loader-visible code/data must stay identical.
        assert allocated_sections(data) == allocated_sections(original), 'Packaged Office code/data differs from manifest library: ' + entry['name']
    assert 'libs/arm64-v8a/libentry.so' in names and 'libs/x86_64/libentry.so' in names
    assert not any('liboffice_probe' in name or 'office-stage' in name for name in names)
    assert package.read('resources/rawfile/office/manifest.json') == manifest_bytes
    archive = package.read('resources/rawfile/office/runtime.zip')
    assert sha(archive) == manifest['resourcesSha256']
    with zipfile.ZipFile(BytesIO(archive)) as resources:
        assert resources.testzip() is None
        for entry in manifest['resources']:
            data = resources.read(entry['name'])
            assert len(data) == entry['byteSize'] and sha(data) == entry['sha256'], entry['name']
        for name in ['program/unorc', 'program/fundamentalrc', 'program/services.rdb',
                     'program/types.rdb', 'fonts/DejaVuSans.ttf', 'fonts/DejaVu-LICENSE.txt',
                     'presets/basic/script.xlc', 'LICENSE', 'NOTICE']:
            assert name in resources.namelist()
        resource_size = sum(info.file_size for info in resources.infolist())
    library_names = {abi: {Path(name).name for name in names if name.startswith('libs/' + abi + '/')}
                     for abi in ['arm64-v8a', 'x86_64']}
    for name in sorted(names):
        if not name.startswith('libs/') or name.endswith('/'):
            continue
        data = package.read(name)
        machine, needed, exports, imports, functions = elf(data)
        abi = name.split('/')[1]
        assert machine == (183 if abi == 'arm64-v8a' else 62), name
        triple = 'aarch64-linux-ohos' if abi == 'arm64-v8a' else 'x86_64-linux-ohos'
        directories = [sdk / 'sysroot/usr/lib' / triple, sdk / 'llvm/lib' / triple]
        unresolved = [item for item in needed if item not in library_names[abi] and
                      not any((directory / item).is_file() for directory in directories)]
        assert not unresolved, (name, unresolved)
        if name.endswith('/libsofficeapp.so'):
            assert 'libreofficekit_hook_2' in exports
        if name.endswith('/libetonyek-0.1-lo.so.1'):
            assert not ({'__addtf3', '__extenddftf2', '__floatunsitf', '__multf3'} & imports), 'Office compiler runtime builtins missing'
        if name.endswith('/libgcc3_uno.so'):
            original_functions = elf((root / 'entry/libs/arm64-v8a/libgcc3_uno.so').read_bytes())[4]
            assert '__clear_cache' in original_functions and '__clear_cache' not in imports, 'UNO cache flush must link the SDK builtin instead of calling an unchecked dlsym result'
        if name == 'libs/arm64-v8a/libentry.so':
            assert b'OFFICE_DOCUMENT_LOAD_FAILED' in data and b'NATIVE_PNG_METADATA_UNSUPPORTED' in data
            assert b'OFFICE_UNO_LIBRARY_LOAD_FAILED' in data, 'UNO runtime must be loaded before document components'
            assert not any(symbol.startswith(('jpeg_', 'png_', 'mz_', 'z_crc32', 'z_compress')) for symbol in exports), 'codec interposition risk'
        if name == 'libs/x86_64/libentry.so':
            assert b'OFFICE_ARM64_ONLY' in data and b'OFFICE_DOCUMENT_LOAD_FAILED' not in data
        records.append({'name': name, 'byteSize': len(data), 'sha256': sha(data), 'needed': needed})
    helper = package.read('libs/arm64-v8a/libuno_cppuhelpergcc3.so.3')
    assert b'LO_OFFICE_PROGRAM_URL' in helper or 'LO_OFFICE_PROGRAM_URL'.encode('utf-16le') in helper
    for name in ['formats.json', 'conversion-matrix.json', 'manifest.json']:
        assert package.read('resources/rawfile/format-registry/' + name) == (
            root / 'entry/src/main/resources/rawfile/format-registry' / name).read_bytes()
    matrix = json.loads(package.read('resources/rawfile/format-registry/conversion-matrix.json'))
    assert len(matrix['routes']) == 43
    assert sorted(route['id'] for route in matrix['routes'] if route['status'] == 'experimental') == [
        'docx-pdf', 'jpeg-pdf', 'png-pdf', 'pptx-pdf']
    permissions = json.loads(package.read('module.json'))['module'].get('requestPermissions', [])
    assert not any(item['name'] == 'ohos.permission.INTERNET' for item in permissions)

report = {'scope': 'main ' + args.build_mode + ' signed HAP, ELF exports/direct dependencies and pinned resource bytes only',
          'buildMode': args.build_mode,
          'checkedAtUtc': datetime.now(timezone.utc).isoformat(), 'result': 'passed',
          'hapPath': str(hap), 'hapBytes': hap.stat().st_size, 'hapSha256': sha(hap.read_bytes()),
          'officeLibraryCount': len(manifest['libraries']), 'nativeLibraryCount': len(records),
          'officeResourceFiles': len(manifest['resources']), 'officeResourceUncompressedBytes': resource_size,
          'libreofficekitHook2Exported': True, 'unoProgramPathPatchPackaged': True,
          'unoCacheFlushBuiltinLinked': True, 'officeLibraryManifestCodeAndDataMatch': True,
          'directNeededResolution': 'package files or SDK files; loader namespaces not tested',
          'internetPermissionDeclared': False, 'archiveDefinitionsRetained': 43, 'productScopeRoutes': 4,
          'deviceExecution': 'not performed by this static check',
          'officeInitializationAndConversion': 'not assessed by this static check; see device acceptance report',
          'libraries': records}
if args.test_hap:
    test_hap = args.test_hap.resolve()
    with zipfile.ZipFile(hap) as main_package, zipfile.ZipFile(test_hap) as test_package:
        test_names = set(test_package.namelist())
        assert not any(name.endswith('/libentry.so') for name in test_names), 'Test module must use the main Native engine'
        common_libraries = sorted(name for name in test_names & set(main_package.namelist())
                                  if name.startswith('libs/') and not name.endswith('/'))
        assert len(common_libraries) >= len(manifest['libraries'])
        for name in common_libraries:
            assert sha(main_package.read(name)) == sha(test_package.read(name)), 'Test library differs: ' + name
        for name in ['core-layout.docx', 'core-layout.pptx', 'core-default-font.docx',
                     'core-missing-font.docx', 'core-missing-symbol.docx']:
            matches = [entry for entry in test_names if entry.endswith('/rawfile/' + name)]
            assert len(matches) == 1, name
            assert test_package.read(matches[0]) == (root / 'entry/src/ohosTest/resources/rawfile' / name).read_bytes(), name
    report['testPackage'] = {'hapSha256': sha(test_hap.read_bytes()), 'hapBytes': test_hap.stat().st_size,
                             'noNativeEngineOverride': True, 'matchingNativeLibraries': len(common_libraries),
                             'ownedFixturesMatch': True, 'deviceExecution': 'not performed by this check'}
(root / ('tests/generated/core-routes-' + args.build_mode + '-hap-validation.json')).write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
print(json.dumps({key: value for key, value in report.items() if key != 'libraries'}, indent=2))
