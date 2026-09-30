#include "../core/converter.h"
#include "../core/engine_registry.h"
#include "../napi/bridge_problem.h"
#include <iostream>
#include <stdexcept>
#include <type_traits>

namespace {
void Require(bool condition, const char* reason) {
    if (!condition) throw std::runtime_error(reason);
}
class Cancel final : public hdm::CancellationToken {
public:
    bool IsCancellationRequested() const noexcept override { return false; }
};
class Context final : public hdm::TaskContext {
    Cancel cancel_;
public:
    const hdm::CancellationToken& Cancellation() const noexcept override { return cancel_; }
    hdm::Status CheckBudgetAndDeadline() noexcept override { return {}; }
    hdm::Status ReportProgress(const hdm::ProgressEvent&) noexcept override { return {}; }
    hdm::Status CheckControlAtSafePoint() noexcept override { return {}; }
};
void Errors() {
    // Independent expectations for every protocol-v1 enum value, including unknown fallback.
    const char* expected[] = {"OK", "UNSUPPORTED_FORMAT", "ENGINE_MISSING", "PASSWORD_REQUIRED",
        "PASSWORD_INVALID", "FILE_CORRUPTED", "RESOURCE_LIMIT_EXCEEDED", "OCR_LOW_CONFIDENCE",
        "OUTPUT_VALIDATION_FAILED", "CONVERSION_CANCELLED", "INVALID_REQUEST", "PERMISSION_DENIED",
        "INPUT_NOT_FOUND", "STORAGE_FULL", "CONVERSION_TIMEOUT", "TASK_INTERRUPTED", "FONT_MISSING",
        "UNSUPPORTED_FEATURE", "INTERNAL_ERROR", "PROTOCOL_INCOMPATIBLE", "CONFIG_INVALID",
        "ABI_UNSUPPORTED", "TASK_BUSY", "IO_ERROR"};
    for (std::size_t i = 0; i < 24; ++i) {
        Require(std::string(hdm::ErrorCodeName(static_cast<hdm::ErrorCode>(i))) == expected[i], "error mapping");
    }
    Require(std::string(hdm::ErrorCodeName(static_cast<hdm::ErrorCode>(999))) == "INTERNAL_ERROR", "unknown error");
}
void Factories() {
    for (const auto* id : {"pdf", "office", "media", "image", "ocr"}) {
        auto first = hdm::CreateConverter(id);
        auto second = hdm::CreateConverter(id);
        Require(first && second && first.get() != second.get(), "factories must create independent instances");
        Require(first->Describe().engine.engineId == id, "factory identity");
        Require(!first->Describe().available, "unverified engines cannot be available");
    }
    for (const auto* id : {"", "IMAGE", "unknown", "../image"}) Require(!hdm::CreateConverter(id), "invalid factory id");
}
void Missing() {
    Context context;
    for (const auto* id : {"pdf", "office", "media", "image", "ocr"}) {
        auto engine = hdm::CreateConverter(id);
        for (const auto& status : {engine->Initialize({}), engine->Validate({}, context), engine->Execute({}, context)}) {
            Require(status.code == hdm::ErrorCode::EngineMissing && !status.IsOk(), "placeholder success");
            Require(status.reason == "ENGINE_NOT_LINKED" && status.module == id, "placeholder diagnostic");
        }
        auto result = engine->CollectOutput(context);
        Require(!result.status.IsOk() && !result.value, "placeholder output");
        engine->Release(); engine->Release();
    }
}
class CountingEngine final : public hdm::IConverter {
    int& released_;
public:
    explicit CountingEngine(int& count) : released_(count) {}
    hdm::ConverterCapabilities Describe() const override { return {}; }
    hdm::Status Initialize(const hdm::EngineInitContext&) override { return {}; }
    hdm::Status Validate(const hdm::ConvertRequest&, const hdm::TaskContext&) const override { return {}; }
    hdm::Status Execute(const hdm::ConvertRequest&, hdm::TaskContext&) override { return {}; }
    hdm::Result<hdm::CandidateOutput> CollectOutput(hdm::TaskContext&) override { return {{}, hdm::CandidateOutput{}}; }
    void Release() noexcept override { ++released_; }
};
void Lease() {
    static_assert(!std::is_copy_constructible<hdm::ConverterLease>::value, "lease must have one owner");
    int released = 0;
    try {
        hdm::ConverterLease lease(std::make_unique<CountingEngine>(released));
        Require(lease.Get() != nullptr, "lease access");
        throw std::runtime_error("scope exit");
    } catch (const std::runtime_error&) {}
    Require(released == 1, "lease must release once on exception");
    { hdm::ConverterLease empty(nullptr); }
    Require(released == 1, "empty lease");
}
void Exception() {
    std::string message = "temporary owned reason";
    hdm::BridgeProblem original(hdm::ErrorCode::IoError, message);
    message.clear();
    const std::exception& generic = original;
    Require(std::string(generic.what()) == "temporary owned reason", "what text lifetime");
    const hdm::BridgeProblem copy = original;
    try { throw copy; }
    catch (const std::exception& copied) { Require(std::string(copied.what()) == "temporary owned reason", "exception copy"); }
    Require(original.code == hdm::ErrorCode::IoError, "error code preservation");
}
}
int main(int argc, char** argv) {
    try {
        Require(argc == 2, "test selection");
        const std::string name = argv[1];
        if (name == "errors") Errors(); else if (name == "factories") Factories();
        else if (name == "missing") Missing(); else if (name == "lease") Lease();
        else if (name == "exception") Exception(); else throw std::runtime_error("unknown test");
        std::cout << "PASS " << name << '\n'; return 0;
    } catch (const std::exception& error) { std::cerr << "FAIL " << error.what() << '\n'; return 1; }
}
