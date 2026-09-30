"""Independent PDF parse, image extraction, raster render, and failure boundaries."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[3]
CLI = Path(sys.argv[1]).resolve()
PDFTOPPM = Path(sys.argv[2]).resolve()
FIXTURES = ROOT / "tmp/pdfs/jpeg-pdf"
OUTPUT = ROOT / "output/pdf"
FIXTURES.mkdir(parents=True, exist_ok=True)
OUTPUT.mkdir(parents=True, exist_ok=True)
CASES = []


def run_case(name, source, output, args=(), expected=None):
    process = subprocess.run([str(CLI), str(source), str(output), *args], capture_output=True,
                             text=True, encoding="utf-8", timeout=60)
    if expected is None:
        assert process.returncode == 0, (name, process.stderr)
        result = json.loads(process.stdout)
        assert result["state"] == "prototype_candidate" and result["embeddedJpegIdentical"]
        assert result["tempPeak"] <= 536870912 and result["trackedAllocationPeak"] <= 201326592
        return result
    assert process.returncode != 0 and not output.exists(), (name, process.stdout, process.stderr)
    result = json.loads(process.stderr)
    assert result["code"] == expected, (name, result)
    assert not list(output.parent.glob(output.name + ".hdm-*")), (name, "temporary artifact leaked")
    CASES.append({"case": name, "result": "passed", "code": expected})
    return result


rgb = Image.new("RGB", (240, 180))
for y in range(rgb.height):
    for x in range(rgb.width):
        rgb.putpixel((x, y), (x, y, (x * 3 + y * 5) % 256))
gray = rgb.convert("L")
for name, image, opts, render_dpi in [
    ("rgb", rgb, {"quality": 93, "subsampling": 0}, 72),
    ("gray_300dpi", gray, {"quality": 94, "dpi": (300, 300)}, 300),
]:
    source = FIXTURES / f"{name}.jpg"
    output = OUTPUT / f"isolated-{name}.pdf"
    image.save(source, "JPEG", **opts)
    if output.exists():
        output.unlink()  # exact local test artifact owned by this script
    result = run_case(name, source, output)
    reader = PdfReader(output, strict=True)
    assert len(reader.pages) == 1 and len(reader.pages[0].images) == 1
    page = reader.pages[0]
    xobject = page["/Resources"]["/XObject"]["/Im0"].get_object()
    assert str(xobject["/Filter"]) == "/DCTDecode"
    assert xobject["/Width"] == image.width and xobject["/Height"] == image.height
    assert xobject._data == source.read_bytes()  # independently parsed JPEG stream
    width_pt, height_pt = float(page.mediabox.width), float(page.mediabox.height)
    assert abs(width_pt - image.width * 72 / render_dpi) < .00001
    assert abs(height_pt - image.height * 72 / render_dpi) < .00001
    rendered_prefix = FIXTURES / f"rendered-{name}"
    subprocess.run([str(PDFTOPPM), "-f", "1", "-l", "1", "-singlefile", "-r", str(render_dpi),
                    "-png", str(output), str(rendered_prefix)], check=True, timeout=60, capture_output=True)
    rendered = Image.open(str(rendered_prefix) + ".png").convert("RGB")
    original = Image.open(source).convert("RGB")
    assert rendered.size == original.size
    diff = ImageChops.difference(rendered, original)
    mean = sum(ImageStat.Stat(diff).mean) / 3
    # Different JPEG decode/render pipelines need not yield identical RGB samples;
    # the compressed DCT payload itself is separately required to be byte equal.
    assert mean < 6.0, (name, mean)
    CASES.append({"case": name, "result": "passed", "pdfBytes": output.stat().st_size,
                  "inputBytes": source.stat().st_size, "meanAbsoluteRenderedDifference": round(mean, 5),
                  "embeddedJpegIdentical": True, "pages": len(reader.pages), "trackedAllocationPeak": result["trackedAllocationPeak"]})

invalid = FIXTURES / "invalid.jpg"
invalid.write_bytes(b"not a jpeg")
run_case("invalid_magic", invalid, OUTPUT / "invalid.pdf", expected="FILE_CORRUPTED")
source = FIXTURES / "rgb.jpg"
truncated = FIXTURES / "truncated.jpg"
truncated.write_bytes(source.read_bytes()[:-16])
run_case("truncated", truncated, OUTPUT / "truncated.pdf", expected="FILE_CORRUPTED")
trailing = FIXTURES / "trailing.jpg"
trailing.write_bytes(source.read_bytes() + b"unexpected-trailer")
run_case("trailing_data_rejected", trailing, OUTPUT / "trailing.pdf", expected="FILE_CORRUPTED")
progressive = FIXTURES / "progressive.jpg"
rgb.save(progressive, "JPEG", progressive=True)
run_case("progressive_rejected", progressive, OUTPUT / "progressive.pdf", expected="UNSUPPORTED_FEATURE")
exif = FIXTURES / "exif.jpg"
metadata = Image.Exif()
metadata[274] = 6
rgb.save(exif, "JPEG", exif=metadata)
run_case("exif_orientation_rejected", exif, OUTPUT / "exif.pdf", expected="UNSUPPORTED_FEATURE")
icc = FIXTURES / "icc.jpg"
rgb.save(icc, "JPEG", icc_profile=b"test-profile")
run_case("icc_rejected", icc, OUTPUT / "icc.pdf", expected="UNSUPPORTED_FEATURE")
cmyk = FIXTURES / "cmyk.jpg"
rgb.convert("CMYK").save(cmyk, "JPEG")
run_case("cmyk_rejected", cmyk, OUTPUT / "cmyk.pdf", expected="UNSUPPORTED_FEATURE")
run_case("pixel_limit", source, OUTPUT / "pixels.pdf", ["--max-pixels", "10"], "RESOURCE_LIMIT_EXCEEDED")
limited = FIXTURES / "large_multichunk.jpg"
noise = Image.frombytes("RGB", (768, 512), bytes((i * 67 + (i // 31) * 19) % 256 for i in range(768 * 512 * 3)))
noise.save(limited, "JPEG", quality=95, subsampling=0)
assert limited.stat().st_size > 65536
large_output = OUTPUT / "isolated-large_multichunk.pdf"
if large_output.exists():
    large_output.unlink()  # exact local test artifact owned by this script
large_result = run_case("large_multichunk", limited, large_output)
large_page = PdfReader(large_output, strict=True).pages[0]
assert large_page["/Resources"]["/XObject"]["/Im0"].get_object()._data == limited.read_bytes()
CASES.append({"case": "large_multichunk", "result": "passed", "inputBytes": limited.stat().st_size,
              "trackedAllocationPeak": large_result["trackedAllocationPeak"], "embeddedJpegIdentical": True})
wide = FIXTURES / "wide_memory.jpg"
wide_image = Image.new("RGB", (32768, 1))
for x in range(wide_image.width):
    wide_image.putpixel((x, 0), (x % 256, (x // 3) % 256, (x // 7) % 256))
wide_image.save(wide, "JPEG", quality=95, dpi=(300, 300))
memory_output = OUTPUT / "memory.pdf"
if memory_output.exists():
    memory_output.unlink()  # exact local artifact from a prior test attempt
run_case("decoder_memory_limit", wide, memory_output, ["--max-native-bytes", "131072"],
         "RESOURCE_LIMIT_EXCEEDED")
run_case("temp_limit", source, OUTPUT / "temp.pdf", ["--max-temp-bytes", str(source.stat().st_size + 10)],
         "RESOURCE_LIMIT_EXCEEDED")
run_case("cancel", source, OUTPUT / "cancel.pdf", ["--cancel"], "CONVERSION_CANCELLED")
existing = OUTPUT / "existing.pdf"
existing.write_bytes(b"protected")
process = subprocess.run([str(CLI), str(source), str(existing)], capture_output=True, text=True, timeout=60)
assert process.returncode and existing.read_bytes() == b"protected"
assert json.loads(process.stderr)["code"] == "INVALID_REQUEST"
CASES.append({"case": "no_overwrite", "result": "passed"})

report = {"scope": "isolated_host_prototype_with_independent_pdf_parser_and_renderer", "result": "passed",
          "source": "Pillow generated fixtures", "parser": "pypdf strict", "renderer": "Poppler pdftoppm",
          "testedCases": len(CASES), "cases": CASES, "applicationIntegrated": False,
          "deviceExecution": "not_executed", "realRoutesAvailable": 0}
(ROOT / "tests/generated/jpeg-pdf-prototype-integration.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"result": "passed", "testedCases": len(CASES)}))
