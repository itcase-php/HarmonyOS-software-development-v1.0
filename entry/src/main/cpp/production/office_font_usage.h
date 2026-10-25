#pragma once
#include "office_input.h"
#include <map>
#include <functional>
namespace hdm::production {
void ResolveOfficeFontUsage(const std::map<std::string,std::string>& parts,const std::string& format,OfficeInput& result);
Status ValidateOfficeFontUsage(const std::vector<OfficeFontUse>& uses,
    const std::function<bool(const std::string&)>& familyAvailable,
    const std::function<bool(const std::string&,std::uint32_t)>& hasGlyph,
    bool approved,std::vector<FontDiagnostic>& diagnostics);
}
