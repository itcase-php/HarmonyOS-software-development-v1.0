#pragma once
#include "stream.h"
#include <optional>
#include <vector>

namespace hdm::prototype {
struct StyleRef {
    std::string id, parentId;
    int priority{};
    std::optional<std::uint32_t> backgroundArgb;
    std::optional<double> opacity;
};
struct ResolvedStyle { std::uint32_t backgroundArgb{0xffffffff}; double opacity{1}; };
ResolvedStyle ResolveStyle(const std::vector<StyleRef>& styles, const std::string& id);
struct ImageRef {
    std::uint32_t widthPx{}, heightPx{}, components{};
    std::uint64_t byteSize{};
    double widthPt{}, heightPt{};
    std::string styleId;
    std::uint32_t orientation{1};
    std::vector<unsigned char> iccProfile{};
};
struct PageNode { double widthPt{}, heightPt{}; std::vector<ImageRef> images; };
struct DocumentIR { std::uint32_t version{1}; std::vector<PageNode> pages; std::vector<StyleRef> styles; };
struct IRVisitor {
    virtual ~IRVisitor() = default;
    virtual void Document(const DocumentIR&) {}
    virtual void Page(const PageNode&) {}
    virtual void Image(const ImageRef&) {}
};
void Visit(const DocumentIR& document, IRVisitor& visitor);
struct IRBuilder {
    virtual ~IRBuilder() = default;
    virtual DocumentIR Build(IStream& source, IFile& ownedSpool, const ResourceBudget&, const Control&) = 0;
};
struct PdfCandidate {
    std::uint64_t bytes{}, imageOffset{}, imageBytes{}, trackedAllocationPeak{}, tempPeak{};
    bool payloadIdentical{};
    std::uint32_t iccBytes{}, iccComponents{};
};
struct IRWriter {
    virtual ~IRWriter() = default;
    virtual PdfCandidate Write(const DocumentIR&, IStream& ownedSpool, ISink&, const ResourceBudget&, const Control&) = 0;
};
// Bounded payload identity guard. Full PDF syntax/render validation is separate.
struct IFidelityValidator {
    virtual ~IFidelityValidator() = default;
    virtual bool Validate(IStream& sourceJpeg, IStream& candidatePdf, const PdfCandidate&,
        const std::string& profileId, const Control&) = 0;
};
class JpegIRBuilder final : public IRBuilder {
public:
    std::uint64_t trackedAllocationPeak{};
    DocumentIR Build(IStream&, IFile&, const ResourceBudget&, const Control&) override;
};
class PdfIRWriter final : public IRWriter {
public:
    PdfCandidate Write(const DocumentIR&, IStream&, ISink&, const ResourceBudget&, const Control&) override;
};
class ExactJpegValidator final : public IFidelityValidator {
public:
    bool Validate(IStream&, IStream&, const PdfCandidate&, const std::string&, const Control&) override;
};
struct PrototypeResult { DocumentIR document; PdfCandidate candidate; };
PrototypeResult Convert(IStream&, IFile& ownedSpool, IFile& candidatePdf, const ResourceBudget&, const Control&);
}
