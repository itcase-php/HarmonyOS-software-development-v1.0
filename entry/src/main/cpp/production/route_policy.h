#pragma once
#include "../generated/registry_metadata.h"
#include <string>

namespace hdm::production {
// Test eligibility is compiled from the same build mode and whitelist as ArkTS.
// This implementation has no release-qualified conversion routes.
inline bool IsDebugRouteExecutable(const std::string& routeId) {
#ifdef HDM_NATIVE_DEBUG
    if (routeId != kJpegPdfRouteId || std::string(kJpegPdfRouteStatus) != "experimental") return false;
    for (const auto* allowed : kDebugRouteIds) if (routeId == allowed) return true;
#else
    (void)routeId;
#endif
    return false;
}
}
