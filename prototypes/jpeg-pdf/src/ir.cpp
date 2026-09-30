#include "ir.h"
#include <algorithm>
#include <cmath>
#include <set>
namespace hdm::prototype {
ResolvedStyle ResolveStyle(const std::vector<StyleRef>& styles, const std::string& id) {
    if (styles.size() > 64 || id.size() > 128) throw BridgeProblem(ErrorCode::ResourceLimitExceeded, "PROTOTYPE_STYLE_LIMIT");
    std::set<std::string> ids;
    for (const auto& style : styles) {
        if (style.id.empty() || style.id.size() > 128 || style.parentId.size() > 128 || !ids.insert(style.id).second ||
            (style.opacity && (!std::isfinite(*style.opacity) || *style.opacity < 0 || *style.opacity > 1)))
            throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_STYLE_INVALID");
    }
    std::vector<const StyleRef*> chain; std::set<std::string> seen; std::string current = id;
    while (!current.empty()) {
        if (!seen.insert(current).second) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_STYLE_CYCLE");
        const auto found = std::find_if(styles.begin(), styles.end(), [&](const StyleRef& style) { return style.id == current; });
        if (found == styles.end()) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_STYLE_NOT_FOUND");
        chain.push_back(&*found); current = found->parentId;
    }
    std::reverse(chain.begin(), chain.end());
    std::stable_sort(chain.begin(), chain.end(), [](auto a, auto b) { return a->priority < b->priority; });
    ResolvedStyle result;
    for (const auto* style : chain) {
        if (style->backgroundArgb) result.backgroundArgb = *style->backgroundArgb;
        if (style->opacity) result.opacity = *style->opacity;
    }
    return result;
}
void Visit(const DocumentIR& document, IRVisitor& visitor) {
    if (document.version != 1) throw BridgeProblem(ErrorCode::ProtocolIncompatible, "PROTOTYPE_IR_VERSION");
    visitor.Document(document);
    for (const auto& page : document.pages) { visitor.Page(page); for (const auto& image : page.images) visitor.Image(image); }
}
}
