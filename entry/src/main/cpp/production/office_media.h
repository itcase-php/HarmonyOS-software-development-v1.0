#pragma once
#include "../core/converter.h"
#include <string>
namespace hdm::production {
// Validate encoded bitmaps before Office import can replace a broken image with a placeholder.
void ValidateOfficeMedia(const std::string&,const std::string&,const ResourceBudget&);
}
