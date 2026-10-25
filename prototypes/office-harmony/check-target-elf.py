"""Inspect target ELF files and resolve DT_NEEDED names against build/SDK files.

This does not execute OHOS code, check runtime namespaces, or validate conversion.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import pathlib
import re
import struct
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("build", type=pathlib.Path)
parser.add_argument("sdk", type=pathlib.Path)
parser.add_argument("report", type=pathlib.Path)
args = parser.parse_args()
program = args.build / "instdir/program"
readelf = args.sdk / "llvm/bin/llvm-readelf"
sdk_paths = [args.sdk / "sysroot/usr/lib/aarch64-linux-ohos",
             args.sdk / "llvm/lib/aarch64-linux-ohos"]
rows = []
for path in sorted(program.iterdir()):
    if not path.is_file():
        continue
    with path.open("rb") as stream:
        header = stream.read(20)
    if header[:4] != b"\x7fELF":
        continue
    output = subprocess.check_output([str(readelf), "--dynamic", "--version-info", str(path)], text=True)
    needed = re.findall(r"\(NEEDED\).*?Shared library: \[([^\]]+)\]", output)
    unresolved = [name for name in needed
                  if not any((directory / name).is_file() for directory in [program, *sdk_paths])]
    version_needs = output.partition("Version needs section")[2]
    rows.append({"name": path.name, "bytes": path.stat().st_size,
                 "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                 "elfClass": header[4], "machine": struct.unpack_from("<H", header, 18)[0],
                 "needed": needed, "unresolvedNeeded": unresolved,
                 "glibcVersionDependency": bool(re.search(r"GLIBC(?:XX)?_[0-9]", version_needs))})
required = ["libsofficeapp.so", "libswlo.so", "libsdlo.so", "libpdffilterlo.so"]
names = {row["name"] for row in rows}
missing = [name for name in required if name not in names]
lok_hook = False
if "libsofficeapp.so" in names:
    symbols = subprocess.check_output([str(args.sdk / "llvm/bin/llvm-nm"), "--dynamic",
                                       "--defined-only", str(program / "libsofficeapp.so")], text=True)
    lok_hook = any(line.split()[-1] == "libreofficekit_hook_2" for line in symbols.splitlines() if line.split())
passed = bool(rows) and not missing and lok_hook and all(
    row["elfClass"] == 2 and row["machine"] == 183
    and not row["glibcVersionDependency"] and not row["unresolvedNeeded"] for row in rows)
report = {"scope": "static_target_elf_and_direct_needed_file_resolution_only",
          "checkedAtUtc": datetime.now(timezone.utc).isoformat(),
          "result": "passed" if passed else "failed", "missingRequiredLibraries": missing,
          "libreofficekitHook2Exported": lok_hook,
          "sdkRuntimePackaging": "not_verified", "deviceExecution": "not_executed", "files": rows}
args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({key: value for key, value in report.items() if key != "files"}, indent=2))
print("Checked ELF files:", len(rows))
for row in rows:
    if row["unresolvedNeeded"]:
        print(row["name"], "unresolved:", ", ".join(row["unresolvedNeeded"]))
raise SystemExit(0 if passed else 2)
