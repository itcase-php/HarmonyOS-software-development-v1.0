#pragma once
#include "../core/converter.h"
#include <filesystem>
#include <vector>
namespace hdm::production {
struct OfficeInput {
    std::vector<std::string> fonts;
    std::uint32_t slides{};
    ContentExpectation content;
    bool hasPrivateGlyphs{};
};
// Read the package, not its extension. No archive entries are extracted to disk.
OfficeInput InspectOffice(const std::filesystem::path&,const std::string& format,const ResourceBudget&);
}
