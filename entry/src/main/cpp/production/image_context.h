#pragma once
#include "../core/converter.h"
#include "../../../../../prototypes/jpeg-pdf/include/ir.h"
#include <chrono>
#include <optional>

namespace hdm::production {
class ImageContext final : public TaskContext, public CancellationToken {
public:
    ImageContext(prototype::IFile& source, prototype::IFile& spool, prototype::IFile& candidate,
        const std::atomic<bool>& cancelled, std::chrono::steady_clock::time_point deadline,
        std::string candidateRelativePath)
        : source(source), spool(spool), candidate(candidate), candidateRelativePath(std::move(candidateRelativePath)),
          cancelled_(cancelled), deadline_(deadline) {}
    const CancellationToken& Cancellation() const noexcept override { return *this; }
    bool IsCancellationRequested() const noexcept override { return cancelled_.load(); }
    Status CheckBudgetAndDeadline() noexcept override {
        if (cancelled_.load()) { Status status; status.code=ErrorCode::ConversionCancelled;
            status.reason="NATIVE_CANCELLED"; return status; }
        if (std::chrono::steady_clock::now() >= deadline_) { Status status; status.code=ErrorCode::ConversionTimeout;
            status.reason="NATIVE_TIMEOUT"; return status; }
        return {};
    }
    Status ReportProgress(const ProgressEvent&) noexcept override { return CheckBudgetAndDeadline(); }
    Status CheckControlAtSafePoint() noexcept override { return CheckBudgetAndDeadline(); }
    prototype::Control Control() const {
        return [this]() { return const_cast<ImageContext*>(this)->CheckBudgetAndDeadline().code; };
    }
    prototype::IFile& source;
    prototype::IFile& spool;
    prototype::IFile& candidate;
    std::string candidateRelativePath;
    std::optional<prototype::PrototypeResult> result;
private:
    const std::atomic<bool>& cancelled_;
    std::chrono::steady_clock::time_point deadline_;
};
} // namespace hdm::production
