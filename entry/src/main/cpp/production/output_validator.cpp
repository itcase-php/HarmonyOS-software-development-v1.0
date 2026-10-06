#include "output_validator.h"
#include <array>
#include <string>

namespace hdm::production {
namespace {
std::string Read(prototype::IStream& file,std::uint64_t offset,std::size_t length) {
    if (offset>file.Size() || length>file.Size()-offset || length>1024) return {};
    std::string text(length,'\0'); file.Seek(offset);
    std::size_t done=0;
    while (done<length) {
        const auto count=file.Read(text.data()+done,length-done);
        if (!count || count>length-done) return {};
        done+=count;
    }
    return text;
}
bool Decimal(const std::string& text,std::uint64_t& value) {
    if (text.empty()) return false;
    value=0;
    for (const auto ch:text) {
        if (ch<'0' || ch>'9' || value>(UINT64_MAX-static_cast<unsigned>(ch-'0'))/10) return false;
        value=value*10+static_cast<unsigned>(ch-'0');
    }
    return true;
}
}
bool ValidateKnownPdf(prototype::IStream& pdf, const prototype::PdfCandidate& candidate) {
    try {
        const auto length=pdf.Size();
        if (length!=candidate.bytes || candidate.imageBytes==0 || candidate.imageOffset>length ||
            candidate.imageBytes>length-candidate.imageOffset || length<250) return false;
        if (Read(pdf,0,9)!="%PDF-1.4\n") return false;
        const auto tailStart=length>128?length-128:0;
        const auto tail=Read(pdf,tailStart,static_cast<std::size_t>(length-tailStart));
        const auto marker=tail.rfind("startxref\n");
        if (marker==std::string::npos || tail.substr(tail.size()-6)!="%%EOF\n") return false;
        const auto end=tail.find('\n',marker+10);
        if (end==std::string::npos) return false;
        std::uint64_t xref{};
        if (!Decimal(tail.substr(marker+10,end-(marker+10)),xref) || xref>=length) return false;
        const auto header=Read(pdf,xref,29);
        if (header!="xref\n0 6\n0000000000 65535 f \n") return false;
        std::array<std::uint64_t,6> offsets{};
        for (std::size_t i=1;i<offsets.size();++i) {
            const auto line=Read(pdf,xref+29+(i-1)*20,20);
            if (line.size()!=20 || line.substr(10)!=" 00000 n \n" || !Decimal(line.substr(0,10),offsets[i]) ||
                offsets[i]>=xref || (i>1 && offsets[i]<=offsets[i-1])) return false;
            if (Read(pdf,offsets[i],std::to_string(i).size()+7)!=std::to_string(i)+" 0 obj\n") return false;
        }
        if (offsets[4]>=candidate.imageOffset || candidate.imageOffset+candidate.imageBytes>=offsets[5]) return false;
        const auto pages=Read(pdf,offsets[2],static_cast<std::size_t>(offsets[3]-offsets[2]));
        if (pages.find("/Count 1")==std::string::npos) return false;
        const auto image=Read(pdf,offsets[4],static_cast<std::size_t>(candidate.imageOffset-offsets[4]));
        if (image.find("/Subtype /Image")==std::string::npos ||
            image.find("/Filter /DCTDecode")==std::string::npos ||
            image.find("/Length "+std::to_string(candidate.imageBytes)+" >>\nstream\n")==std::string::npos) return false;
        return true;
    } catch (...) { return false; }
}
} // namespace hdm::production
