#include "ir.h"
#include <algorithm>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
using namespace hdm;
using namespace hdm::prototype;
namespace {
void Require(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
template<typename Run> void Error(Run run, ErrorCode code) {
    try { run(); }
    catch (const BridgeProblem& error) { Require(error.code == code, "wrong error code"); return; }
    throw std::runtime_error("expected failure");
}
struct MemoryFile final : IFile {
    std::string bytes; std::size_t position{};
    explicit MemoryFile(std::string data = "") : bytes(std::move(data)) {}
    std::size_t Read(void* output, std::size_t capacity) override {
        const auto count = std::min(capacity, bytes.size() - position);
        std::copy_n(bytes.data()+position, count, static_cast<char*>(output)); position += count; return count;
    }
    void Seek(std::uint64_t offset) override {
        if (offset > bytes.size()) throw BridgeProblem(ErrorCode::IoError, "TEST_SEEK"); position = static_cast<std::size_t>(offset);
    }
    std::uint64_t Size() override { return bytes.size(); }
    std::size_t Write(const void* input, std::size_t count) override {
        if (position + count > bytes.size()) bytes.resize(position + count);
        std::copy_n(static_cast<const char*>(input), count, bytes.begin()+position); position += count; return count;
    }
    void Flush() override {}
};
struct PartialSink final : ISink {
    std::uint64_t bytes{}; std::size_t maxPerCall{137};
    std::size_t Write(const void*, std::size_t count) override { const auto n = std::min(count,maxPerCall); bytes += n; return n; }
};
struct SyntheticInput final : IStream {
    std::uint64_t position{}, total{100ULL*1024*1024}; std::size_t maximumRead{};
    std::size_t Read(void* output, std::size_t capacity) override {
        maximumRead = std::max(maximumRead,capacity);
        const auto n = static_cast<std::size_t>(std::min<std::uint64_t>(capacity,total-position));
        std::fill_n(static_cast<unsigned char*>(output),n,0x41); position += n; return n;
    }
    void Seek(std::uint64_t p) override { position = p; }
    std::uint64_t Size() override { return total; }
};
void Streams() {
    SyntheticInput input; PartialSink sink; std::uint64_t written{};
    CopyChunks(input,sink,input.total,{},written,input.total,kChunkBytes);
    Require(written==input.total && sink.bytes==input.total, "100 MiB was not copied");
    Require(input.maximumRead==kChunkBytes, "input was buffered beyond one chunk");
    input.Seek(0); written=0; int checks=0;
    Error([&] { CopyChunks(input,sink,input.total,[&] { return ++checks > 10 ? ErrorCode::ConversionCancelled : ErrorCode::Ok; },
        written,input.total,kChunkBytes); },ErrorCode::ConversionCancelled);
    Require(written < input.total, "cancellation did not stop streaming");
    Error([&] { std::uint64_t n=0; input.Seek(0); CopyChunks(input,sink,1,{},n,1,kChunkBytes-1); }, ErrorCode::ResourceLimitExceeded);
    MemoryFile shortSource("ab"), target; std::uint64_t n=0;
    Error([&] { CopyChunks(shortSource,target,3,{},n,3,kChunkBytes); }, ErrorCode::IoError);
    PartialSink zero; zero.maxPerCall=0;
    Error([&] { n=0; WriteAll(zero,"a",1,{},n,1); }, ErrorCode::IoError);
    Error([&] { n=0; WriteAll(target,"ab",2,{},n,1); }, ErrorCode::ResourceLimitExceeded);
}
void IR() {
    const std::vector<StyleRef> styles{{"base","",0,0xff000000,1.0},{"child","base",0,0xffffffff,std::nullopt}};
    const auto style=ResolveStyle(styles,"child"); Require(style.backgroundArgb==0xffffffff && style.opacity==1,"inheritance failed");
    auto higher=styles; higher[0].priority=5;
    Require(ResolveStyle(higher,"child").backgroundArgb==0xff000000,"priority failed");
    auto cycle=styles;cycle[0].parentId="child";
    Error([&]{ResolveStyle(cycle,"child");},ErrorCode::InvalidRequest);
    Error([&]{ResolveStyle(styles,"missing");},ErrorCode::InvalidRequest);
    struct Count final : IRVisitor { int docs{},pages{},images{}; void Document(const DocumentIR&) override { docs++; }
        void Page(const PageNode&) override { pages++; } void Image(const ImageRef&) override { images++; } } count;
    DocumentIR document; document.pages.push_back({72,72,{{72,72,3,100,72,72,""}}});
    Visit(document,count); Require(count.docs==1&&count.pages==1&&count.images==1,"visitor skipped a node");
    document.version=2; Error([&]{Visit(document,count);},ErrorCode::ProtocolIncompatible);
}
void Budgets() {
    MemoryFile source("not a jpeg"),spool; ResourceBudget budget{};
    budget.maxInputBytes=104857600; budget.maxBatchBytes=314572800; budget.maxTempBytes=536870912;
    budget.maxNativeBytes=201326592; budget.maxPages=300; budget.maxPixels=16000000; budget.maxThreads=2; budget.timeoutMs=180000;
    JpegIRBuilder builder;
    Error([&]{ auto bad=budget; bad.maxInputBytes=1; builder.Build(source,spool,bad,{}); },ErrorCode::ResourceLimitExceeded);
    Error([&]{ auto bad=budget; bad.maxNativeBytes=1; builder.Build(source,spool,bad,{}); },ErrorCode::InvalidRequest);
    Error([&]{ auto bad=budget; bad.maxTempBytes=1; builder.Build(source,spool,bad,{}); },ErrorCode::ResourceLimitExceeded);
    Error([&]{ builder.Build(source,spool,budget,[]{return ErrorCode::ConversionCancelled;}); },ErrorCode::ConversionCancelled);
    Error([&]{ builder.Build(source,spool,budget,[]{return ErrorCode::ConversionTimeout;}); },ErrorCode::ConversionTimeout);
    Error([&]{ builder.Build(source,spool,budget,{}); },ErrorCode::FileCorrupted);
}
void Payload() {
    MemoryFile source("JPEG"), pdf("xxJPEGyy"); PdfCandidate candidate{};
    candidate.bytes=8;candidate.imageOffset=2;candidate.imageBytes=4;
    ExactJpegValidator validator;
    Require(validator.Validate(source,pdf,candidate,"image_pdf",{}),"identical payload failed");
    Error([&]{validator.Validate(source,pdf,candidate,"other",{});},ErrorCode::InvalidRequest);
    pdf.bytes[3]='X'; Require(!validator.Validate(source,pdf,candidate,"image_pdf",{}),"changed payload accepted");
    candidate.imageBytes=10;
    Error([&]{validator.Validate(source,pdf,candidate,"image_pdf",{});},ErrorCode::OutputValidationFailed);
}
}
int main(int argc,char**argv) {
    try { Require(argc==2,"test name needed");
        const std::map<std::string,void(*)()> cases{{"streams",Streams},{"ir",IR},{"budgets",Budgets},{"payload",Payload}};
        cases.at(argv[1])();std::cout<<"PASS "<<argv[1]<<'\n';return 0;
    } catch(const std::exception& error) { std::cerr<<error.what()<<'\n';return 1; }
}
