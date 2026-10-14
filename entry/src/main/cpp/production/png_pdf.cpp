#include "png_pdf.h"
#include "../napi/bridge_problem.h"
#include <png.h>
#include <zlib.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <cstdio>
#include <string>

namespace hdm::production {
namespace {
void Check(const prototype::Control& control) {
    const auto code=control();
    if (code!=ErrorCode::Ok) throw BridgeProblem(code,"NATIVE_PNG_INTERRUPTED");
}
std::uint32_t Big(const unsigned char* p) {
    return (std::uint32_t(p[0])<<24)|(std::uint32_t(p[1])<<16)|(std::uint32_t(p[2])<<8)|p[3];
}
std::vector<unsigned char> Compress(const std::vector<unsigned char>& input) {
    uLongf size=compressBound(static_cast<uLong>(input.size()));
    std::vector<unsigned char> output(size);
    if (compress2(output.data(),&size,input.data(),static_cast<uLong>(input.size()),Z_BEST_SPEED)!=Z_OK)
        throw BridgeProblem(ErrorCode::InternalError,"NATIVE_PNG_COMPRESSION");
    output.resize(size); return output;
}
}
PngPixels ReadPng(prototype::IFile& source,const ResourceBudget& budget,const prototype::Control& control) {
    Check(control);
    const auto bytes=source.Size();
    if (bytes<33 || bytes>budget.maxInputBytes || bytes>100ULL*1024*1024)
        throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_PNG_INPUT_LIMIT");
    source.Seek(0);
    std::vector<unsigned char> data(static_cast<std::size_t>(bytes));
    std::size_t read=0;
    while (read<data.size()) { Check(control); const auto n=source.Read(data.data()+read,std::min<std::size_t>(65536,data.size()-read));
        if (!n) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_TRUNCATED"); read+=n; }
    if (png_sig_cmp(data.data(),0,8)!=0 || std::memcmp(data.data()+12,"IHDR",4)!=0)
        throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_SIGNATURE");
    PngPixels pixels; pixels.width=Big(data.data()+16); pixels.height=Big(data.data()+20);
    pixels.pageWidth=pixels.width*0.75; pixels.pageHeight=pixels.height*0.75;
    const auto count=std::uint64_t(pixels.width)*pixels.height;
    // RGBA, separated channels, compressed channels, input and codec reserve coexist.
    if (!count || count>budget.maxPixels || count>16000000 ||
        bytes+count*14+8*1024*1024>budget.maxNativeBytes)
        throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_PNG_MEMORY_LIMIT");
    if (data[24]>8) throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_PNG_16BIT_UNSUPPORTED");
    bool ended=false;
    for (std::size_t offset=8; offset+12<=data.size();) {
        Check(control); const auto size=Big(data.data()+offset);
        if (size>data.size()-offset-12) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_CHUNK");
        const auto* type=data.data()+offset+4;
        if (crc32(0,type,size+4)!=Big(data.data()+offset+8+size))
            throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_CRC");
        // No silent ICC/gamma conversion, animation dropping or EXIF rotation loss.
        if (!std::memcmp(type,"iCCP",4) || !std::memcmp(type,"cHRM",4) || !std::memcmp(type,"eXIf",4) ||
            !std::memcmp(type,"acTL",4) || !std::memcmp(type,"cICP",4) || !std::memcmp(type,"mDCV",4) || !std::memcmp(type,"cLLI",4))
            throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_PNG_METADATA_UNSUPPORTED");
        if (!std::memcmp(type,"gAMA",4) && (size!=4 || (Big(type+4)!=45455 && Big(type+4)!=45454)))
            throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_PNG_GAMMA_UNSUPPORTED");
        if (!std::memcmp(type,"pHYs",4)) {
            if (size!=9) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_DENSITY_INVALID");
            const auto x=Big(type+4),y=Big(type+8); const auto unit=type[12];
            if (!x || !y || unit>1) throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_PNG_DENSITY_UNSUPPORTED");
            if (unit==1) {
                pixels.pageWidth=pixels.width*72/(x*0.0254); pixels.pageHeight=pixels.height*72/(y*0.0254);
            } else if (x!=y) {
                throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_PNG_DENSITY_UNSUPPORTED");
            }
        }
        offset+=size+12;
        if (!std::memcmp(type,"IEND",4)) {
            if (size || offset!=data.size()) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_TRAILING_DATA");
            ended=true; break;
        }
    }
    if (!ended) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_TRUNCATED");
    if (pixels.pageWidth<0.01 || pixels.pageHeight<0.01 || pixels.pageWidth>14400 || pixels.pageHeight>14400)
        throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_PNG_PAGE_SIZE_LIMIT");
    png_image image{}; image.version=PNG_IMAGE_VERSION;
    struct Cleanup { png_image* image; ~Cleanup() { png_image_free(image); } } cleanup{&image};
    if (!png_image_begin_read_from_memory(&image,data.data(),data.size()))
        throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_DECODE");
    image.format=PNG_FORMAT_RGBA;
    pixels.rgba.resize(static_cast<std::size_t>(count)*4);
    if (!png_image_finish_read(&image,nullptr,pixels.rgba.data(),0,nullptr))
        throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_PNG_DECODE");
    Check(control); return pixels;
}
std::uint64_t WritePngPdf(const PngPixels& pixels,prototype::IFile& pdf,const ResourceBudget& budget,const prototype::Control& control) {
    Check(control);
    const auto count=static_cast<std::size_t>(pixels.width)*pixels.height;
    std::vector<unsigned char> rgb(count*3),alpha(count);
    bool transparent=false;
    for (std::size_t i=0;i<count;++i) {
        if (i%65536==0) Check(control);
        std::memcpy(rgb.data()+i*3,pixels.rgba.data()+i*4,3);
        alpha[i]=pixels.rgba[i*4+3]; transparent|=alpha[i]!=255;
    }
    const auto color=Compress(rgb); const auto mask=transparent?Compress(alpha):std::vector<unsigned char>{};
    std::vector<std::uint64_t> offsets{0}; std::uint64_t position=0;
    auto bytes=[&](const void* p,std::size_t n) {
        Check(control);
        if (position+n>budget.maxTempBytes) throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_PNG_OUTPUT_LIMIT");
        const auto* data=static_cast<const unsigned char*>(p);
        while (n) {
            const auto count=std::min<std::size_t>(n,65536);
            prototype::WriteAll(pdf,data,count,control,position,budget.maxTempBytes);
            data+=count; n-=count;
        }
    };
    auto text=[&](const std::string& s) { bytes(s.data(),s.size()); };
    auto object=[&](const std::string& body) { offsets.push_back(position); text(std::to_string(offsets.size()-1)+" 0 obj\n"+body+"\nendobj\n"); };
    const auto width=std::to_string(pixels.pageWidth),height=std::to_string(pixels.pageHeight);
    text("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");
    object("<< /Type /Catalog /Pages 2 0 R >>");
    object("<< /Type /Pages /Count 1 /Kids [3 0 R] >>");
    object("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "+width+" "+height+"] /Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>");
    const auto paint="q\n"+width+" 0 0 "+height+" 0 0 cm\n/Im0 Do\nQ\n";
    object("<< /Length "+std::to_string(paint.size())+" >>\nstream\n"+paint+"endstream");
    auto image=[&](const std::vector<unsigned char>& payload,const char* space,bool softMask) {
        offsets.push_back(position); text(std::to_string(offsets.size()-1)+" 0 obj\n<< /Type /XObject /Subtype /Image /Width "+
            std::to_string(pixels.width)+" /Height "+std::to_string(pixels.height)+" /ColorSpace /"+space+
            " /BitsPerComponent 8 /Filter /FlateDecode /Length "+std::to_string(payload.size())+
            (softMask?" /SMask 6 0 R":"")+" >>\nstream\n");
        bytes(payload.data(),payload.size()); text("\nendstream\nendobj\n");
    };
    image(color,"DeviceRGB",transparent); if (transparent) image(mask,"DeviceGray",false);
    const auto xref=position; text("xref\n0 "+std::to_string(offsets.size())+"\n0000000000 65535 f \n");
    for (std::size_t i=1;i<offsets.size();++i) { char line[32]; std::snprintf(line,sizeof(line),"%010llu 00000 n \n",static_cast<unsigned long long>(offsets[i])); text(line); }
    text("trailer\n<< /Size "+std::to_string(offsets.size())+" /Root 1 0 R >>\nstartxref\n"+std::to_string(xref)+"\n%%EOF\n");
    pdf.Flush(); return position;
}
}
