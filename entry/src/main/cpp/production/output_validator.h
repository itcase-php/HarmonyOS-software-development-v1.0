#pragma once
#include "../../../../../prototypes/jpeg-pdf/include/ir.h"

namespace hdm::production {
// Validate the fixed writer's structure without loading the JPEG or PDF into memory.
// The independent PDF parser/renderer integration test remains a separate release gate.
bool ValidateKnownPdf(prototype::IStream& pdf, const prototype::PdfCandidate& candidate);
} // namespace hdm::production
