"""Prepare engine libraries and offline resources for the isolated signed Stage app."""
from pathlib import Path
import shutil
import zipfile

source = Path.home() / '.cache/hdm-office/26.2.6.2/device-runtime'
app = Path('/mnt/d/HarmonyOS/harmonyOS/tmp/offline-engines/office-stage-probe/entry')
libraries = app / 'libs/arm64-v8a'
libraries.mkdir(parents=True, exist_ok=True)
count = 0
for path in (source / 'program').iterdir():
    if not path.is_file() or '.so' not in path.name:
        continue
    with path.open('rb') as stream:
        is_elf = stream.read(4) == b'\x7fELF'
    if is_elf:
        shutil.copyfile(path, libraries / path.name)
        count += 1
    elif path.name.endswith('-gdb.py') and (libraries / path.name).is_file():
        (libraries / path.name).unlink()
archive = app / 'src/main/resources/rawfile/office-resources.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=1) as target:
    for directory in ['program', 'share', 'fonts']:
        for path in (source / directory).rglob('*'):
            if not path.is_file() or path.is_symlink():
                continue
            with path.open('rb') as stream:
                if stream.read(4) == b'\x7fELF':
                    continue
            target.write(path, path.relative_to(source).as_posix())
    for name in ['LICENSE', 'NOTICE', 'CREDITS.fodt']:
        if (source / name).is_file():
            target.write(source / name, name)
print(f'Packaged {count} native libraries; resources {archive.stat().st_size} bytes')
