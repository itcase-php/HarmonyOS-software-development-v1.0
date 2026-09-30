// Generated indexed factory table. Real adapters keep their engineId and factory signature.
#include "engine_registry.h"
#include <unordered_map>
namespace hdm {
std::unique_ptr<IConverter> CreatePdfConverter();
std::unique_ptr<IConverter> CreateOfficeConverter();
std::unique_ptr<IConverter> CreateMediaConverter();
std::unique_ptr<IConverter> CreateImageConverter();
std::unique_ptr<IConverter> CreateOcrConverter();
std::unique_ptr<IConverter> CreateConverter(const std::string& engineId) {
    using Factory = std::unique_ptr<IConverter> (*)();
    static const std::unordered_map<std::string, Factory> registrations = {
        {"pdf", CreatePdfConverter},
        {"office", CreateOfficeConverter},
        {"media", CreateMediaConverter},
        {"image", CreateImageConverter},
        {"ocr", CreateOcrConverter},
    };
    const auto entry = registrations.find(engineId);
    return entry == registrations.end() ? nullptr : entry->second();
}
}
