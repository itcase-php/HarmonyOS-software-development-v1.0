#include "../../core/missing_converter.h"
namespace hdm {
std::unique_ptr<IConverter> CreatePdfConverter() { return std::make_unique<MissingConverter>("pdf"); }
}
