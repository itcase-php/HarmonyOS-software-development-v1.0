#include "../../core/missing_converter.h"
namespace hdm {
std::unique_ptr<IConverter> CreateOcrConverter() { return std::make_unique<MissingConverter>("ocr"); }
}
