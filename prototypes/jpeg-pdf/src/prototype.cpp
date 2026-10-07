#include "ir.h"
#include "jpeg_probe.h"
#include <array>
#include <algorithm>
#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>
namespace hdm::prototype {
namespace {
struct ProbeIO {
    IStream& input;
    IFile& spool;
    const ResourceBudget& budget;
    const Control& control;
    std::uint64_t bytes{};
};
extern "C" int ProbeRead(void* opaque, unsigned char* buffer, size_t capacity, size_t* count) noexcept {
    auto& io = *static_cast<ProbeIO*>(opaque);
    try {
        CheckControl(io.control);
        *count = io.input.Read(buffer, capacity);
        if (*count > capacity || io.bytes > io.budget.maxInputBytes || *count > io.budget.maxInputBytes - io.bytes)
            return static_cast<int>(ErrorCode::ResourceLimitExceeded);
        WriteAll(io.spool, buffer, *count, io.control, io.bytes, io.budget.maxTempBytes);
        return 0;
    } catch (const BridgeProblem& error) { return static_cast<int>(error.code); }
    catch (const std::bad_alloc&) { return static_cast<int>(ErrorCode::ResourceLimitExceeded); }
    catch (...) { return static_cast<int>(ErrorCode::IoError); }
}
extern "C" int ProbeCheck(void* opaque) noexcept {
    auto& io = *static_cast<ProbeIO*>(opaque);
    try { CheckControl(io.control); return 0; }
    catch (const BridgeProblem& error) { return static_cast<int>(error.code); }
    catch (...) { return static_cast<int>(ErrorCode::InternalError); }
}
std::string Number(double number) {
    if (!std::isfinite(number) || number < 0 || number > 14400)
        throw BridgeProblem(ErrorCode::ResourceLimitExceeded, "PROTOTYPE_PAGE_GEOMETRY");
    std::ostringstream stream; stream.imbue(std::locale::classic()); stream << std::fixed << std::setprecision(6) << number;
    return stream.str();
}
std::string ImageMatrix(const ImageRef& image) {
    const double w = image.widthPt, h = image.heightPt;
    const std::array<std::array<double,6>,8> matrices{{
        {{w,0,0,h,0,0}}, {{-w,0,0,h,w,0}}, {{-w,0,0,-h,w,h}}, {{w,0,0,-h,0,h}},
        {{0,-h,-w,0,w,h}}, {{0,-h,w,0,0,h}}, {{0,h,w,0,0,0}}, {{0,h,-w,0,w,0}}
    }};
    std::string text;
    for (double value : matrices[image.orientation-1]) {
        if (!text.empty()) text += " ";
        text += value < 0 ? "-"+Number(-value) : value == 0 ? "0" : Number(value);
    }
    return text;
}
void NeedSinglePageImage(const DocumentIR& document) {
    if (document.version != 1 || document.pages.size() != 1 || document.pages[0].images.size() != 1)
        throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_IR_SHAPE");
    const auto& page = document.pages[0]; const auto& image = page.images[0];
    if (!image.widthPx || !image.heightPx || image.byteSize == 0 || (image.components != 1 && image.components != 3) ||
        page.widthPt != image.widthPt || page.heightPt != image.heightPt || page.widthPt <= 0 || page.heightPt <= 0 ||
        image.orientation < 1 || image.orientation > 8 || image.iccProfile.size() > 65536 ||
        (!image.iccProfile.empty() && (image.iccProfile.size() < 132 || image.iccProfile[64] ||
            image.iccProfile[65] || image.iccProfile[66] || image.iccProfile[67] > 3)))
        throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_IMAGE_GEOMETRY");
    const auto style = ResolveStyle(document.styles, image.styleId);
    if (style.backgroundArgb != 0xffffffff || style.opacity != 1)
        throw BridgeProblem(ErrorCode::UnsupportedFeature, "PROTOTYPE_STYLE_UNSUPPORTED");
}
}
DocumentIR JpegIRBuilder::Build(IStream& source, IFile& spool, const ResourceBudget& budget, const Control& control) {
    if (!budget.maxInputBytes || !budget.maxPixels || !budget.maxTempBytes || !budget.maxPages || !budget.maxThreads ||
        !budget.timeoutMs || budget.maxNativeBytes < 2 * kChunkBytes || budget.maxBatchBytes < budget.maxInputBytes)
        throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_BUDGET_INVALID");
    if (spool.Size()) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_SPOOL_NOT_EMPTY");
    const auto size = source.Size();
    if (!size || size > budget.maxInputBytes || size > budget.maxTempBytes)
        throw BridgeProblem(ErrorCode::ResourceLimitExceeded, "PROTOTYPE_INPUT_LIMIT");
    source.Seek(0); ProbeIO io{source, spool, budget, control}; HdmJpegInfo info{};
    const int result = hdm_probe_jpeg(ProbeRead, ProbeCheck, &io, budget.maxNativeBytes, budget.maxPixels, &info);
    trackedAllocationPeak = info.peak;
    if (result) {
        const auto code = static_cast<ErrorCode>(result);
        throw BridgeProblem(code, code == ErrorCode::UnsupportedFeature ? "PROTOTYPE_JPEG_SUBSET" : "PROTOTYPE_JPEG_PROBE_FAILED");
    }
    spool.Flush();
    if (io.bytes != size || spool.Size() != size) throw BridgeProblem(ErrorCode::FileCorrupted, "PROTOTYPE_INPUT_CHANGED");
    double dpiX = 72, dpiY = 72;
    if (info.density_unit == 1) { dpiX = info.density_x; dpiY = info.density_y; }
    if (info.density_unit == 2) { dpiX = info.density_x * 2.54; dpiY = info.density_y * 2.54; }
    if (info.exif_dpi_x > 0) { dpiX = info.exif_dpi_x; dpiY = info.exif_dpi_y; }
    double widthPt = info.width * 72.0 / dpiX, heightPt = info.height * 72.0 / dpiY;
    if (info.orientation >= 5) std::swap(widthPt,heightPt);
    (void)Number(widthPt); (void)Number(heightPt);
    DocumentIR document;
    ImageRef image{info.width, info.height, info.components, size, widthPt, heightPt, "", info.orientation, {}};
    image.iccProfile.assign(info.icc_profile,info.icc_profile+info.icc_size);
    PageNode page{widthPt,heightPt,{}};
    page.images.push_back(std::move(image)); document.pages.push_back(std::move(page));
    return document;
}
PdfCandidate PdfIRWriter::Write(const DocumentIR& document, IStream& spool, ISink& output,
    const ResourceBudget& budget, const Control& control) {
    NeedSinglePageImage(document);
    const auto& page = document.pages[0]; const auto& image = page.images[0];
    if (spool.Size() != image.byteSize || budget.maxPages < 1 || image.byteSize > budget.maxInputBytes ||
        budget.maxTempBytes < image.byteSize || budget.maxNativeBytes < 2 * kChunkBytes)
        throw BridgeProblem(ErrorCode::ResourceLimitExceeded, "PROTOTYPE_WRITER_BUDGET");
    const std::uint64_t maximum = std::min<std::uint64_t>(budget.maxTempBytes - image.byteSize, 9999999999ULL);
    const bool hasIcc = !image.iccProfile.empty();
    const std::size_t objectCount = hasIcc ? 7 : 6;
    std::uint64_t written = 0; std::array<std::uint64_t, 7> offsets{};
    auto append = [&](const std::string& value) { WriteAll(output, value.data(), value.size(), control, written, maximum); };
    auto object = [&](int index, const std::string& body) {
        offsets[static_cast<size_t>(index)] = written;
        append(std::to_string(index) + " 0 obj\n" + body + "\nendobj\n");
    };
    append(hasIcc ? "%PDF-1.7\n%\xe2\xe3\xcf\xd3\n" : "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n");
    object(1, "<< /Type /Catalog /Pages 2 0 R >>");
    object(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
    const std::string geometry = Number(page.widthPt) + " " + Number(page.heightPt);
    object(3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + geometry +
        "] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>");
    offsets[4] = written;
    const std::string color = hasIcc ? "[/ICCBased 6 0 R]" : image.components == 1 ? "/DeviceGray" : "/DeviceRGB";
    const std::array<const char*,4> intents{{"Perceptual","RelativeColorimetric","Saturation","AbsoluteColorimetric"}};
    const std::string intent = hasIcc ? " /Intent /"+std::string(intents[image.iccProfile[67]]) : "";
    append("4 0 obj\n<< /Type /XObject /Subtype /Image /Width " + std::to_string(image.widthPx) +
        " /Height " + std::to_string(image.heightPx) + " /ColorSpace " + color + intent +
        " /BitsPerComponent 8 /Filter /DCTDecode /Interpolate false /Length " +
        std::to_string(image.byteSize) + " >>\nstream\n");
    const std::uint64_t imageOffset = written;
    spool.Seek(0); CopyChunks(spool, output, image.byteSize, control, written, maximum, budget.maxNativeBytes);
    append("\nendstream\nendobj\n");
    const std::string contents = "q\n" + ImageMatrix(image) + " cm\n/Im0 Do\nQ\n";
    offsets[5] = written;
    append("5 0 obj\n<< /Length " + std::to_string(contents.size()) + " >>\nstream\n" + contents + "endstream\nendobj\n");
    if (hasIcc) {
        offsets[6] = written;
        append("6 0 obj\n<< /N " + std::to_string(image.components) + " /Length " +
            std::to_string(image.iccProfile.size()) + " >>\nstream\n");
        WriteAll(output,image.iccProfile.data(),image.iccProfile.size(),control,written,maximum);
        append("\nendstream\nendobj\n");
    }
    const std::uint64_t xref = written;
    append("xref\n0 " + std::to_string(objectCount) + "\n0000000000 65535 f \n");
    for (size_t i = 1; i < objectCount; ++i) {
        std::ostringstream line; line.imbue(std::locale::classic());
        line << std::setw(10) << std::setfill('0') << offsets[i] << " 00000 n \n";
        append(line.str());
    }
    append("trailer\n<< /Size " + std::to_string(objectCount) + " /Root 1 0 R >>\nstartxref\n" + std::to_string(xref) + "\n%%EOF\n");
    return {written, imageOffset, image.byteSize, kChunkBytes, image.byteSize + written, false,
        static_cast<std::uint32_t>(image.iccProfile.size()), hasIcc ? image.components : 0};
}
bool ExactJpegValidator::Validate(IStream& sourceJpeg, IStream& candidatePdf, const PdfCandidate& candidate,
    const std::string& profileId, const Control& control) {
    if (profileId != "image_pdf") throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_VALIDATION_PROFILE");
    if (candidate.imageOffset > candidate.bytes || candidate.imageBytes > candidate.bytes - candidate.imageOffset ||
        candidate.bytes != candidatePdf.Size() || candidate.imageBytes != sourceJpeg.Size())
        throw BridgeProblem(ErrorCode::OutputValidationFailed, "PROTOTYPE_CANDIDATE_LENGTH");
    sourceJpeg.Seek(0); candidatePdf.Seek(candidate.imageOffset);
    std::array<unsigned char, kChunkBytes> left{}, right{};
    std::uint64_t remaining = candidate.imageBytes;
    while (remaining) {
        CheckControl(control);
        const auto count = static_cast<std::size_t>(std::min<std::uint64_t>(remaining, kChunkBytes));
        std::size_t got = 0, other = 0;
        while (got < count) { auto n = sourceJpeg.Read(left.data() + got, count - got); if (!n || n > count - got) return false; got += n; }
        while (other < count) { auto n = candidatePdf.Read(right.data() + other, count - other); if (!n || n > count - other) return false; other += n; }
        if (!std::equal(left.begin(), left.begin() + count, right.begin())) return false;
        remaining -= count;
    }
    return true;
}
PrototypeResult Convert(IStream& input, IFile& spool, IFile& pdf, const ResourceBudget& budget, const Control& control) {
    if (pdf.Size()) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_OUTPUT_NOT_EMPTY");
    JpegIRBuilder builder; auto document = builder.Build(input, spool, budget, control);
    PdfIRWriter writer; auto candidate = writer.Write(document, spool, pdf, budget, control);
    pdf.Flush();
    ExactJpegValidator validator;
    if (!validator.Validate(spool, pdf, candidate, "image_pdf", control))
        throw BridgeProblem(ErrorCode::OutputValidationFailed, "PROTOTYPE_JPEG_PAYLOAD_MISMATCH");
    candidate.payloadIdentical = true;
    candidate.trackedAllocationPeak = std::max(builder.trackedAllocationPeak, 2 * kChunkBytes);
    return {std::move(document), candidate};
}
}
