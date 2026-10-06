"""Check the pinned upstream compiler prerequisite; this is not a port build."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess

PIN = "6804c10b45d52787c1e865e3ad192d7dfc7d4862"
parser = argparse.ArgumentParser()
parser.add_argument("source", type=pathlib.Path)
parser.add_argument("sdk", type=pathlib.Path)
args = parser.parse_args()
revision = subprocess.check_output(["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True).strip()
if revision != PIN:
    raise SystemExit("Expected the approved source revision")
configure = (args.source / "configure.ac").read_bytes()
text = configure.decode().replace("\r\n", "\n")
guard = re.search(r'if test "\$CLANGVER" -ge (\d+); then.*?must be at least Clang (\d+)', text, re.S)
if not guard:
    raise SystemExit("Cannot locate the upstream compiler prerequisite")
compiler = args.sdk / "llvm/bin/clang"
version = subprocess.check_output([str(compiler), "--target=aarch64-linux-ohos", "-E", "-P", "-x", "c", "-"],
    input="__clang_major__.__clang_minor__.__clang_patchlevel__\n", text=True).strip().replace(" ", "")
major, minor, patch = map(int, version.split("."))
numeric = major * 10000 + min(minor, 99) * 100 + min(patch, 99)
compatible = numeric >= int(guard.group(1))
print(json.dumps({"scope": "upstream_compiler_prerequisite_only", "revision": revision,
    "configureSha256Lf": hashlib.sha256(text.encode()).hexdigest(), "target": "aarch64-linux-ohos",
    "sdk": json.loads((args.sdk / "oh-uni-package.json").read_text()), "compilerVersion": version,
    "requiredClangMajor": int(guard.group(2)), "result": "passed" if compatible else "blocked",
    "officeBuild": "not_completed", "officeDeviceConversion": "not_executed"}, indent=2))
raise SystemExit(0 if compatible else 2)
