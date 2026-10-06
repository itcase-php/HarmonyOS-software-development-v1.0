// Isolated feasibility harness. Never linked into the converter's release HAP.
#include <napi/native_api.h>
#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>
#include <chrono>
#include <memory>
#include <string>
#include <sys/resource.h>

namespace {
struct Probe {
    napi_deferred deferred{};
    napi_async_work work{};
    std::string models, input, text;
    const char* error{};
    double elapsedMs{};
    int confidence{};
    long peakKiB{};
};
bool ReadText(napi_env env, napi_value value, std::string& result) {
    napi_valuetype type{};
    size_t length{};
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string ||
        napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || !length || length > 4096) return false;
    result.resize(length + 1);
    if (napi_get_value_string_utf8(env, value, result.data(), result.size(), &length) != napi_ok) return false;
    result.resize(length); return true;
}
void Execute(napi_env, void* data) noexcept {
    auto& probe = *static_cast<Probe*>(data);
    auto start = std::chrono::steady_clock::now();
    try {
        // Only the generated, bounded PGM corpus is supported by this harness.
        std::unique_ptr<PIX, void(*)(PIX*)> image(pixRead(probe.input.c_str()), [](PIX* value) { pixDestroy(&value); });
        if (!image || pixGetWidth(image.get()) > 2000 || pixGetHeight(image.get()) > 2000) {
            probe.error = "PROBE_RASTER_INVALID"; return;
        }
        tesseract::TessBaseAPI api;
        if (api.Init(probe.models.c_str(), "eng+chi_sim", tesseract::OEM_LSTM_ONLY) != 0) {
            probe.error = "PROBE_MODELS_NOT_LOADED"; return;
        }
        api.SetPageSegMode(tesseract::PSM_SINGLE_BLOCK);
        api.SetImage(image.get()); api.SetSourceResolution(300);
        if (api.Recognize(nullptr) != 0) { probe.error = "PROBE_RECOGNIZE_FAILED"; return; }
        std::unique_ptr<char[]> text(api.GetUTF8Text());
        if (!text) { probe.error = "PROBE_TEXT_MISSING"; return; }
        probe.text = text.get(); probe.confidence = api.MeanTextConf(); api.End();
        rusage usage{};
        if (getrusage(RUSAGE_SELF, &usage) == 0) probe.peakKiB = usage.ru_maxrss;
    } catch (...) { probe.error = "PROBE_ENGINE_EXCEPTION"; }
    probe.elapsedMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
}
void Complete(napi_env env, napi_status status, void* data) noexcept {
    std::unique_ptr<Probe> probe(static_cast<Probe*>(data));
    napi_value value{};
    try {
    if (status != napi_ok || probe->error) {
        const char* error = status != napi_ok ? "PROBE_ASYNC_FAILED" : probe->error;
        if (napi_create_string_utf8(env, error, NAPI_AUTO_LENGTH, &value) == napi_ok)
            (void)napi_reject_deferred(env, probe->deferred, value);
    } else {
        // Fixed test text only; measurements are not a document fidelity score.
        std::string result = "Tesseract 5.5.1 / Leptonica 1.85.0\n" + probe->text +
            "\nelapsedMs=" + std::to_string(probe->elapsedMs) + "\nprocessPeakKiB=" +
            std::to_string(probe->peakKiB) + "\nengineMeanConfidence=" + std::to_string(probe->confidence);
        if (napi_create_string_utf8(env, result.c_str(), result.size(), &value) == napi_ok)
            (void)napi_resolve_deferred(env, probe->deferred, value);
        else if (napi_get_undefined(env, &value) == napi_ok) (void)napi_reject_deferred(env, probe->deferred, value);
    }
    } catch (...) {
        if (napi_create_string_utf8(env, "PROBE_COMPLETION_FAILED", NAPI_AUTO_LENGTH, &value) == napi_ok)
            (void)napi_reject_deferred(env, probe->deferred, value);
    }
    (void)napi_delete_async_work(env, probe->work);
}
napi_value RunImpl(napi_env env, napi_callback_info info) {
    size_t count = 2; napi_value args[2]{};
    auto probe = std::make_unique<Probe>();
    if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 2 ||
        !ReadText(env, args[0], probe->models) || !ReadText(env, args[1], probe->input)) {
        (void)napi_throw_type_error(env, nullptr, "PROBE_ARGUMENTS"); return nullptr;
    }
    napi_value promise{}, name{};
    if (napi_create_promise(env, &probe->deferred, &promise) != napi_ok) return nullptr;
    if (napi_create_string_utf8(env, "OfflineOcrProbe", NAPI_AUTO_LENGTH, &name) != napi_ok ||
        napi_create_async_work(env, nullptr, name, Execute, Complete, probe.get(), &probe->work) != napi_ok ||
        napi_queue_async_work(env, probe->work) != napi_ok) {
        if (probe->work) (void)napi_delete_async_work(env, probe->work);
        napi_value error{};
        if (napi_create_string_utf8(env, "PROBE_QUEUE_FAILED", NAPI_AUTO_LENGTH, &error) == napi_ok)
            (void)napi_reject_deferred(env, probe->deferred, error);
        return promise;
    }
    probe.release(); return promise;
}
napi_value Run(napi_env env, napi_callback_info info) noexcept {
    try { return RunImpl(env, info); }
    catch (...) { (void)napi_throw_error(env, nullptr, "PROBE_ARGUMENT_ALLOCATION"); return nullptr; }
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor descriptor = {"run", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr};
    if (napi_define_properties(env, exports, 1, &descriptor) != napi_ok) return nullptr;
    return exports;
}
napi_module module = {1, 0, nullptr, Init, "hdm_ocr_probe", nullptr, {nullptr}};
}
extern "C" __attribute__((constructor)) void RegisterOcrProbe() { napi_module_register(&module); }
