#include "../../core/missing_converter.h"
namespace hdm {
std::unique_ptr<IConverter> CreateImageConverter() { return std::make_unique<MissingConverter>("image"); }
}
