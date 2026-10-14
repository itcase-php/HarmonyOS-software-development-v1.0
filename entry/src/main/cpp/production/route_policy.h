#pragma once
#include "../generated/registry_metadata.h"
#include <string>

namespace hdm::production {
// Product execution is independent of Debug/Release. Engine, input and output
// checks still apply; enabling execution does not manufacture device evidence.
inline bool IsProductRouteExecutable(const std::string& routeId) {
    // Unsupported definitions remain archived, but cannot execute.
    for (const auto* allowed : kProductRouteIds) if (routeId == allowed) return true;
    return false;
}
}
