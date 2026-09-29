// Generated factory table. Real adapters keep their engineId and factory signature.
#include "engine_registry.h"
namespace hdm {
std::unique_ptr<IConverter> CreatePdfConverter();
std::unique_ptr<IConverter> CreateOfficeConverter();
std::unique_ptr<IConverter> CreateMediaConverter();
std::unique_ptr<IConverter> CreateImageConverter();
std::unique_ptr<IConverter> CreateOcrConverter();
struct Registration { const char* id; std::unique_ptr<IConverter> (*create)(); };
const Registration registrations[] = {
    {"pdf", CreatePdfConverter},
    {"office", CreateOfficeConverter},
    {"media", CreateMediaConverter},
    {"image", CreateImageConverter},
    {"ocr", CreateOcrConverter},
};
std::unique_ptr<IConverter> CreateConverter(const std::string& engineId) {
    for (const auto& entry : registrations) if (engineId == entry.id) return entry.create();
    return nullptr;
}
}
