#pragma once
#include "napi/native_api.h"
namespace hdm {
napi_value ProductionInitialize(napi_env, napi_callback_info);
napi_value ProductionRegister(napi_env, napi_callback_info);
napi_value ProductionProbe(napi_env, napi_callback_info);
napi_value ProductionExecute(napi_env, napi_callback_info);
napi_value ProductionSubscribe(napi_env, napi_callback_info);
napi_value ProductionUnsubscribe(napi_env, napi_callback_info);
napi_value ProductionCancel(napi_env, napi_callback_info);
napi_value ProductionPause(napi_env, napi_callback_info);
napi_value ProductionResume(napi_env, napi_callback_info);
napi_value ProductionReleaseTask(napi_env, napi_callback_info);
napi_value ProductionReleaseArtifact(napi_env, napi_callback_info);
napi_value ProductionShutdown(napi_env, napi_callback_info);
} // namespace hdm
