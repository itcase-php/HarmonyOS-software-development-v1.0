#include "../production/output_validator.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
struct MemoryFile final : hdm::prototype::IFile {
    std::string bytes; std::size_t position{};
    std::size_t Read(void* output,std::size_t count) override {
        const auto n=std::min(count,bytes.size()-position);
        std::copy_n(bytes.data()+position,n,static_cast<char*>(output)); position+=n; return n;
    }
    void Seek(std::uint64_t offset) override {
        if (offset>bytes.size()) throw std::runtime_error("seek"); position=static_cast<std::size_t>(offset);
    }
    std::uint64_t Size() override { return bytes.size(); }
    std::size_t Write(const void* data,std::size_t count) override {
        if (position+count>bytes.size()) bytes.resize(position+count);
        std::copy_n(static_cast<const char*>(data),count,bytes.begin()+position); position+=count; return count;
    }
    void Flush() override {}
};
void Require(bool value,const char* reason) { if (!value) throw std::runtime_error(reason); }
void ReplaceOnce(std::string& text,const std::string& old,const std::string& replacement) {
    const auto pos=text.find(old); if (pos==std::string::npos || old.size()!=replacement.size()) throw std::runtime_error("fixture");
    text.replace(pos,old.size(),replacement);
}
}
int main() {
    try {
        using namespace hdm;
        MemoryFile jpeg,pdf;
        jpeg.bytes="tiny synthetic payload";
        prototype::DocumentIR document;
        document.pages.push_back({72,72,{{1,1,3,jpeg.Size(),72,72,""}}});
        ResourceBudget budget; budget.maxInputBytes=1024; budget.maxBatchBytes=2048;
        budget.maxTempBytes=655360; budget.maxNativeBytes=655360;
        budget.maxPages=1; budget.maxPixels=1; budget.maxThreads=1; budget.timeoutMs=1000;
        prototype::PdfIRWriter writer;
        const auto candidate=writer.Write(document,jpeg,pdf,budget,{});
        Require(production::ValidateKnownPdf(pdf,candidate),"generated PDF structure rejected");
        const auto original=pdf.bytes;
        ReplaceOnce(pdf.bytes,"/Count 1","/Count 2");
        Require(!production::ValidateKnownPdf(pdf,candidate),"page count mutation accepted");
        pdf.bytes=original;
        ReplaceOnce(pdf.bytes,"/DCTDecode","/ABCDecode");
        Require(!production::ValidateKnownPdf(pdf,candidate),"image filter mutation accepted");
        pdf.bytes=original;
        ReplaceOnce(pdf.bytes,"xref\n0 6","xref\n0 7");
        Require(!production::ValidateKnownPdf(pdf,candidate),"xref mutation accepted");
        pdf.bytes=original;
        ReplaceOnce(pdf.bytes,"%%EOF\n","%%E0F\n");
        Require(!production::ValidateKnownPdf(pdf,candidate),"trailer mutation accepted");
        std::cout<<"PASS output validator\n"; return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
