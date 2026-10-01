#include "../../core/converter.h"
#include "../../napi/bridge_problem.h"
#include "../../production/image_context.h"
#include "../../generated/registry_metadata.h"
#include <memory>

namespace hdm {
namespace {
Status Failure(ErrorCode code, const char* reason) {
    Status status; status.code=code; status.reason=reason; status.module="image";
    status.messageKey=std::string("errors.")+ErrorCodeName(code); return status;
}
class ImageConverter final : public IConverter {
    ResourceBudget limits_{};
    bool initialized_{};
public:
    ConverterCapabilities Describe() const override {
        ConverterCapabilities capabilities;
        capabilities.engine={"image","1.0.0-experimental","unreleased"};
        capabilities.decoderIds={"jpeg-baseline-sof0-gray-rgb-jfif-v1"};
        capabilities.encoderIds={"pdf-dct-single-page-v1"};
        capabilities.inputSubsetIds={"jpeg-baseline-sof0-jfif-v1"};
        // Linked for internal tests; public route stays gated until device/release evidence.
        capabilities.available=false;
        return capabilities;
    }
    Status Initialize(const EngineInitContext& init) override {
        if (!init.hardLimits.maxInputBytes || !init.hardLimits.maxTempBytes || !init.hardLimits.maxPixels ||
            !init.hardLimits.timeoutMs) return Failure(ErrorCode::InvalidRequest,"IMAGE_BUDGET_INVALID");
        limits_=init.hardLimits; initialized_=true; return {};
    }
    Status Validate(const ConvertRequest& request, const TaskContext& context) const override {
        if (!initialized_) return Failure(ErrorCode::InvalidRequest,"IMAGE_NOT_INITIALIZED");
        if (dynamic_cast<const production::ImageContext*>(&context)==nullptr || request.inputs.size()!=1 ||
            request.inputs[0].sourceFormatId!="jpeg" || request.targetFormatId!="pdf" ||
            request.operation!=Operation::ImagesToPdf || request.plan.routeId!=kJpegPdfRouteId ||
            request.plan.steps.size()!=1 || request.plan.steps[0].executorEngineId!="image" ||
            request.resourceBudget.maxInputBytes>limits_.maxInputBytes ||
            request.resourceBudget.maxTempBytes>limits_.maxTempBytes)
            return Failure(ErrorCode::UnsupportedFormat,"IMAGE_ROUTE_UNSUPPORTED");
        return {};
    }
    Status Execute(const ConvertRequest& request, TaskContext& context) override {
        auto* image=dynamic_cast<production::ImageContext*>(&context);
        if (!image) return Failure(ErrorCode::InvalidRequest,"IMAGE_CONTEXT_REQUIRED");
        try {
            image->result=prototype::Convert(image->source,image->spool,image->candidate,
                request.resourceBudget,image->Control());
            return {};
        } catch (const BridgeProblem& failure) {
            return Failure(failure.code,"IMAGE_CONVERSION_FAILED");
        } catch (const std::bad_alloc&) {
            return Failure(ErrorCode::ResourceLimitExceeded,"IMAGE_ALLOCATION_FAILED");
        } catch (...) {
            return Failure(ErrorCode::InternalError,"IMAGE_CONVERSION_FAILED");
        }
    }
    Result<CandidateOutput> CollectOutput(TaskContext& context) override {
        auto* image=dynamic_cast<production::ImageContext*>(&context);
        if (!image || !image->result || !image->result->candidate.payloadIdentical)
            return {Failure(ErrorCode::OutputValidationFailed,"IMAGE_CANDIDATE_UNVALIDATED"),std::nullopt};
        CandidateOutput output;
        output.files.push_back({"primary","pdf",image->candidateRelativePath,
            image->result->candidate.bytes,std::nullopt});
        output.validationViewRef="image_pdf:payload-identical-v1";
        return {{},std::move(output)};
    }
    void Release() noexcept override { initialized_=false; limits_={}; }
};
}
std::unique_ptr<IConverter> CreateImageConverter() { return std::make_unique<ImageConverter>(); }
} // namespace hdm
