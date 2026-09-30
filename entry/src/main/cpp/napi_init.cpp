#include "napi/native_api.h"
#include "napi/native_bridge.h"
#include <cmath>

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    double value0 = 0, value1 = 0;
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 2 ||
        napi_get_value_double(env, args[0], &value0) != napi_ok ||
        napi_get_value_double(env, args[1], &value1) != napi_ok ||
        !std::isfinite(value0) || !std::isfinite(value1) || !std::isfinite(value0 + value1)) {
        napi_throw_type_error(env, "INVALID_REQUEST", "add requires two finite numbers");
        return nullptr;
    }
    napi_value sum = nullptr;
    if (napi_create_double(env, value0 + value1, &sum) != napi_ok) return nullptr;
    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    if (napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc) != napi_ok) return nullptr;
    return hdm::RegisterNativeBridge(env, exports);
}
EXTERN_C_END

// Value initialization keeps every optional/reserved field zero in C++17.
static napi_module demoModule = [] {
    napi_module module{};
    module.nm_version = 1;
    module.nm_register_func = Init;
    module.nm_modname = "entry";
    return module;
}();

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
