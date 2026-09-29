#include "../../core/missing_converter.h"
namespace hdm {
std::unique_ptr<IConverter> CreateMediaConverter() { return std::make_unique<MissingConverter>("media"); }
}
