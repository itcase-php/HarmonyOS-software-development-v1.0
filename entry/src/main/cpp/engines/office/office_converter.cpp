#include "../../core/missing_converter.h"
namespace hdm {
std::unique_ptr<IConverter> CreateOfficeConverter() { return std::make_unique<MissingConverter>("office"); }
}
