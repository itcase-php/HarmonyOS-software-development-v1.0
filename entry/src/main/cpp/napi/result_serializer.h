#pragma once
#include "native_bridge.h"
#include "../core/converter.h"

namespace hdm {
// Called only on the ArkTS thread completing the native Promise.
napi_value SerializeConvertResult(napi_env env, const ConvertResult& result);
}
