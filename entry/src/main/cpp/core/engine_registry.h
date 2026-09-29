#pragma once
#include "converter.h"
namespace hdm {
std::unique_ptr<IConverter> CreateConverter(const std::string& engineId);
} // namespace hdm
