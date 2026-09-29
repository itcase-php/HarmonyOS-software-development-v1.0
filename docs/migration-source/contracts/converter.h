#pragma once
// C++17 design contract. Core-only: no NAPI, UI, external URI, or database dependency.
#include <atomic>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace hdm {
enum class ErrorCode : std::uint32_t {
    Ok = 0, UnsupportedFormat = 1, EngineMissing = 2, PasswordRequired = 3,
    PasswordInvalid = 4, FileCorrupted = 5, ResourceLimitExceeded = 6,
    OcrLowConfidence = 7, OutputValidationFailed = 8, ConversionCancelled = 9,
    InvalidRequest = 10, PermissionDenied = 11, InputNotFound = 12,
    StorageFull = 13, ConversionTimeout = 14, TaskInterrupted = 15,
    FontMissing = 16, UnsupportedFeature = 17, InternalError = 18,
    ProtocolIncompatible = 19, ConfigInvalid = 20, AbiUnsupported = 21,
    TaskBusy = 22, IoError = 23
};
inline const char* ErrorCodeName(ErrorCode code) noexcept {
    switch (code) {
        case ErrorCode::Ok: return "OK";
        case ErrorCode::UnsupportedFormat: return "UNSUPPORTED_FORMAT";
        case ErrorCode::EngineMissing: return "ENGINE_MISSING";
        case ErrorCode::PasswordRequired: return "PASSWORD_REQUIRED";
        case ErrorCode::PasswordInvalid: return "PASSWORD_INVALID";
        case ErrorCode::FileCorrupted: return "FILE_CORRUPTED";
        case ErrorCode::ResourceLimitExceeded: return "RESOURCE_LIMIT_EXCEEDED";
        case ErrorCode::OcrLowConfidence: return "OCR_LOW_CONFIDENCE";
        case ErrorCode::OutputValidationFailed: return "OUTPUT_VALIDATION_FAILED";
        case ErrorCode::ConversionCancelled: return "CONVERSION_CANCELLED";
        case ErrorCode::InvalidRequest: return "INVALID_REQUEST";
        case ErrorCode::PermissionDenied: return "PERMISSION_DENIED";
        case ErrorCode::InputNotFound: return "INPUT_NOT_FOUND";
        case ErrorCode::StorageFull: return "STORAGE_FULL";
        case ErrorCode::ConversionTimeout: return "CONVERSION_TIMEOUT";
        case ErrorCode::TaskInterrupted: return "TASK_INTERRUPTED";
        case ErrorCode::FontMissing: return "FONT_MISSING";
        case ErrorCode::UnsupportedFeature: return "UNSUPPORTED_FEATURE";
        case ErrorCode::InternalError: return "INTERNAL_ERROR";
        case ErrorCode::ProtocolIncompatible: return "PROTOCOL_INCOMPATIBLE";
        case ErrorCode::ConfigInvalid: return "CONFIG_INVALID";
        case ErrorCode::AbiUnsupported: return "ABI_UNSUPPORTED";
        case ErrorCode::TaskBusy: return "TASK_BUSY";
        case ErrorCode::IoError: return "IO_ERROR";
    }
    return "INTERNAL_ERROR";
}
enum class Stage { Preparing, Executing, Validating, Committing, Cleaning };
enum class Intent { LayoutPreserved, StructuredRebuild, ContentOnly };
enum class QualityMode { Fast, Balanced, HighFidelity };
enum class FidelityTier { Extreme, Standard, Compatible };
enum class Operation { Convert, ImagesToPdf, PdfSplit, PdfMerge, ExtractText, OcrExtract };
enum class MetricState { Measured, Estimated, Unavailable, NotApplicable };
enum class ResultState { Success, Failed, Cancelled };
enum class ValidationState { Passed, Failed, NotEvaluated };

struct Status {
    ErrorCode code{ErrorCode::Ok};
    std::string reason, module, traceId, messageKey;
    Stage stage{Stage::Preparing};
    bool retryable{false};
    std::optional<std::string> detailKey;
    bool IsOk() const noexcept { return code == ErrorCode::Ok; }
};
template <class T> struct Result {
    Status status;
    std::optional<T> value; // Successful Result requires value; checked by caller.
};
struct ResourceBudget {
    std::uint64_t maxInputBytes{}, maxBatchBytes{}, maxNativeBytes{}, maxTempBytes{};
    std::uint32_t maxPages{}, maxPixels{}, maxThreads{}, timeoutMs{};
};
struct PageRange { std::uint32_t first{}, last{}; };
struct PdfOptions {
    std::vector<PageRange> pages;
    double dpi{}, imageQuality{}, paperWidthPt{}, paperHeightPt{}, marginPt{};
    std::uint32_t backgroundArgb{}, rotation{};
    std::string fitMode; // Finite whitelist decoder, not arbitrary dynamic options.
};
struct ImageOptions {
    double quality{};
    std::uint32_t backgroundArgb{};
    std::string metadataPolicy, colorPolicy;
    bool normalizeOrientation{};
};
struct OfficeOptions {
    std::vector<std::string> allowedDegradations;
    bool includeReferencePages{};
    std::string missingFontPolicy;
};
struct AudioOptions {
    std::string codecId, containerId, bitrateMode, metadataPolicy;
    std::uint32_t bitrateBps{}, sampleRateHz{}, channels{};
};
struct OcrOptions {
    std::string modelId, lowConfidencePolicy;
    std::vector<std::string> languages;
};
struct ConvertOptions {
    std::optional<PdfOptions> pdf;
    std::optional<ImageOptions> image;
    std::optional<OfficeOptions> office;
    std::optional<AudioOptions> audio;
    std::optional<OcrOptions> ocr;
};
struct PreparedInput {
    std::string fileId, sourceFormatId, relativePath, sha256;
    std::uint64_t byteSize{};
};
struct PlanStep {
    std::string stepId, executorEngineId, outputFormatId;
    std::vector<std::string> engineIds, inputFormatIds;
    Operation operation{Operation::Convert};
};
struct ApprovedPlan {
    std::string routeId, configVersion, configSha256, policyVersion;
    std::vector<PlanStep> steps;
    std::vector<std::string> fallbackRouteIds, allowedDegradations;
    Intent intent{Intent::ContentOnly};
    FidelityTier minimumTier{FidelityTier::Standard};
};
struct ConvertRequest {
    std::uint32_t schemaVersion{};
    std::string sessionId, taskId, attemptId, workspaceRef, targetFormatId;
    Operation operation{Operation::Convert};
    std::vector<PreparedInput> inputs;
    QualityMode qualityMode{QualityMode::Balanced};
    Intent intent{Intent::ContentOnly};
    ConvertOptions options;
    ResourceBudget resourceBudget;
    ApprovedPlan plan;
};
struct Metric {
    std::string name, unit, algorithmVersion;
    MetricState state{MetricState::Unavailable};
    std::optional<double> value, denominator;
    std::vector<std::string> evidenceRefs;
};
struct FidelityReport {
    std::uint32_t schemaVersion{};
    Intent intent{Intent::ContentOnly};
    FidelityTier requestedTier{FidelityTier::Standard};
    std::optional<FidelityTier> achievedTier;
    std::optional<std::uint32_t> sourcePageCount, outputPageCount;
    std::vector<Metric> metrics;
    std::vector<std::string> fontSubstitutions, unsupportedFeatures, degradations, evidenceRefs;
    bool requiresManualReview{true};
    std::string detectorVersion;
};
struct ConversionWarning {
    ErrorCode code{ErrorCode::UnsupportedFeature};
    std::string reason, messageKey;
    bool requiresManualReview{true};
    std::optional<std::string> evidenceRef;
};
struct Artifact {
    std::string artifactId, role, formatId, internalRef, sha256;
    std::uint64_t byteSize{};
    std::optional<std::uint32_t> pageIndex;
};
struct Validation {
    ValidationState state{ValidationState::NotEvaluated};
    std::string validatorVersion;
    std::vector<std::string> evidenceRefs;
};
struct EngineStamp { std::string engineId, version, buildHash; };
struct ConvertResult {
    std::uint32_t schemaVersion{};
    std::string taskId, attemptId;
    ResultState status{ResultState::Failed};
    std::optional<Status> error;
    std::vector<ConversionWarning> warnings;
    std::vector<Artifact> outputs;
    Validation validation;
    std::optional<FidelityReport> fidelity;
    std::vector<EngineStamp> engines;
    std::uint64_t elapsedMs{}, nativePeakBytes{}, tempPeakBytes{};
};
struct ArtifactCandidate {
    std::string role, formatId, relativePath;
    std::uint64_t byteSize{};
    std::optional<std::uint32_t> pageIndex;
};
struct CandidateOutput {
    std::vector<ArtifactCandidate> files;
    std::string validationViewRef; // Versioned DocumentIR/MediaIR/ImageIR summary.
    std::vector<ConversionWarning> warnings;
};
struct ConverterCapabilities {
    EngineStamp engine;
    std::vector<std::string> decoderIds, encoderIds, inputSubsetIds;
    bool available{false}, supportsPause{false}, supportsCheckpoint{false};
};
struct ProgressEvent {
    std::string taskId, attemptId, unit;
    Stage stage{Stage::Executing};
    std::uint64_t sequence{}, completedUnits{};
    std::optional<std::uint64_t> totalUnits;
    std::optional<double> fraction;
};
enum class ProtectionState { None, Drm, Encrypted, Signed, Unknown };
enum class Availability { Planned, Experimental, Available, Unavailable };
struct RouteCapability {
    std::string routeId, reason, inputSubsetId, validationProfileId;
    Availability availability{Availability::Unavailable};
    bool supportsPause{false}, supportsCheckpoint{false};
    std::vector<std::string> decoderIds, encoderIds;
    std::optional<std::string> releaseEvidenceId;
};
struct CapabilityMatrix {
    std::uint32_t schemaVersion{};
    bool offlineOnly{true};
    std::string abi, configVersion;
    std::vector<EngineStamp> engines;
    std::vector<RouteCapability> routes;
};
struct CapabilityRequest {
    std::uint32_t schemaVersion{};
    std::string sessionId, configVersion;
};
struct ProbeRequest {
    std::uint32_t schemaVersion{};
    std::string sessionId, workspaceRef;
    std::vector<PreparedInput> inputs;
    ResourceBudget resourceBudget;
};
struct InputProbe {
    std::string fileId;
    std::optional<std::string> actualFormatId;
    ProtectionState protection{ProtectionState::Unknown};
    std::optional<std::uint32_t> pageCount;
    bool needsDeepCheck{true};
};
struct SessionInit {
    std::uint32_t schemaVersion{};
    std::string appSandboxRoot, configVersion, configSha256;
};
struct WorkspaceGrant { std::string sessionId, taskId, attemptId, relativeDirectory; };
struct ControlAck {
    std::string taskId, attemptId;
    enum class State { Accepted, TooLate, NotFound, Unsupported };
    State state{State::NotFound};
};
class CancellationToken {
public:
    virtual ~CancellationToken() = default;
    virtual bool IsCancellationRequested() const noexcept = 0;
};
class TaskContext {
public:
    virtual ~TaskContext() = default;
    virtual const CancellationToken& Cancellation() const noexcept = 0;
    virtual Status CheckBudgetAndDeadline() noexcept = 0;
    virtual Status ReportProgress(const ProgressEvent&) noexcept = 0;
    // Safe point may park until resume/cancel; unsupported engines never call it.
    virtual Status CheckControlAtSafePoint() noexcept = 0;
    // Input/resource handles are managed by concrete, audited context implementation.
};
struct EngineInitContext {
    std::string offlineResourceRootRef, policyVersion;
    ResourceBudget hardLimits;
};
class IConverter {
public:
    virtual ~IConverter() = default;
    virtual ConverterCapabilities Describe() const = 0;
    virtual Status Initialize(const EngineInitContext&) = 0;
    virtual Status Validate(const ConvertRequest&, const TaskContext&) const = 0;
    virtual Status Execute(const ConvertRequest&, TaskContext&) = 0;
    virtual Result<CandidateOutput> CollectOutput(TaskContext&) = 0;
    virtual void Release() noexcept = 0;
};
class ConverterLease {
public:
    explicit ConverterLease(std::unique_ptr<IConverter> converter) noexcept
        : converter_(std::move(converter)) {}
    ~ConverterLease() { if (converter_) converter_->Release(); }
    ConverterLease(const ConverterLease&) = delete;
    ConverterLease& operator=(const ConverterLease&) = delete;
    IConverter* Get() const noexcept { return converter_.get(); }
private:
    std::unique_ptr<IConverter> converter_;
};
} // namespace hdm
