#pragma once
#include "napi/native_api.h"
namespace hdm {
napi_value RegisterNativeBridge(napi_env env, napi_value exports);
} // namespace hdm
