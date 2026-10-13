#pragma once
#include "../../../../../prototypes/jpeg-pdf/include/stream.h"
#include <vector>
namespace hdm::production {
struct PngPixels {
    std::uint32_t width{}, height{};
    double pageWidth{}, pageHeight{};
    std::vector<unsigned char> rgba;
};
PngPixels ReadPng(prototype::IFile&, const ResourceBudget&, const prototype::Control&);
std::uint64_t WritePngPdf(const PngPixels&, prototype::IFile&, const ResourceBudget&, const prototype::Control&);
}
