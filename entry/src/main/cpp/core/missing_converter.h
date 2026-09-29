#pragma once
#include "converter.h"

namespace hdm {
// Explicit unavailable implementation. Never produces a candidate or a successful result.
class MissingConverter final : public IConverter {
public:
    explicit MissingConverter(std::string id) : id_(std::move(id)) {}
    ConverterCapabilities Describe() const override {
        ConverterCapabilities caps;
        caps.engine = {id_, "scaffold", "not-linked"};
        return caps;
    }
    Status Initialize(const EngineInitContext&) override { return Missing(); }
    Status Validate(const ConvertRequest&, const TaskContext&) const override { return Missing(); }
    Status Execute(const ConvertRequest&, TaskContext&) override { return Missing(); }
    Result<CandidateOutput> CollectOutput(TaskContext&) override { return {Missing(), std::nullopt}; }
    void Release() noexcept override {}
private:
    Status Missing() const {
        Status status;
        status.code = ErrorCode::EngineMissing;
        status.reason = "ENGINE_NOT_LINKED";
        status.module = id_;
        status.messageKey = "errors.ENGINE_MISSING";
        return status;
    }
    std::string id_;
};
} // namespace hdm
