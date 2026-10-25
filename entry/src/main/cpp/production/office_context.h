#pragma once
#include "image_context.h"
#include <filesystem>
namespace hdm::production {
class OfficeContext final : public TaskContext, public CancellationToken {
public:
    OfficeContext(std::filesystem::path input,std::filesystem::path output,const std::atomic<bool>& cancelled,
        std::chrono::steady_clock::time_point deadline,std::string relative)
        : input(std::move(input)),output(std::move(output)),relative(std::move(relative)),cancelled_(cancelled),deadline_(deadline) {}
    const CancellationToken& Cancellation() const noexcept override { return *this; }
    bool IsCancellationRequested() const noexcept override { return cancelled_.load(); }
    Status CheckBudgetAndDeadline() noexcept override {
        Status status;
        if (cancelled_.load()) { status.code=ErrorCode::ConversionCancelled; status.reason="NATIVE_CANCELLED"; }
        else if (std::chrono::steady_clock::now()>=deadline_) { status.code=ErrorCode::ConversionTimeout; status.reason="NATIVE_TIMEOUT"; }
        return status;
    }
    Status ReportProgress(const ProgressEvent&) noexcept override { return CheckBudgetAndDeadline(); }
    Status CheckControlAtSafePoint() noexcept override { return CheckBudgetAndDeadline(); }
    std::filesystem::path input,output;
    std::string relative;
    std::uint64_t bytes{};
    std::vector<std::string> missingFonts;
    std::vector<FontDiagnostic> fontDiagnostics;
    ContentExpectation content;
private:
    const std::atomic<bool>& cancelled_;
    std::chrono::steady_clock::time_point deadline_;
};
}
