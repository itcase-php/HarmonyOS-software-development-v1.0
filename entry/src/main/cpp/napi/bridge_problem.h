#pragma once
#include "../core/converter.h"
#include <exception>
#include <string>
#include <utility>

namespace hdm {
// Own the diagnostic text: what() remains valid for this exception's lifetime.
class BridgeProblem final : public std::exception {
public:
    ErrorCode code;
    std::string reason;
    BridgeProblem(ErrorCode value, std::string detail) : code(value), reason(std::move(detail)) {}
    const char* what() const noexcept override { return reason.c_str(); }
};
} // namespace hdm
