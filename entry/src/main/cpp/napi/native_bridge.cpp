#include "native_bridge.h"
#ifdef HDM_PRODUCTION_NATIVE
#include "production_napi.h"
#endif
#include "bridge_problem.h"
#include "../core/converter.h"
#include "../generated/registry_metadata.h"
#include <atomic>
#include <chrono>
#include <cmath>
#include <exception>
#include <memory>
#include <stdexcept>

namespace hdm {
namespace {
void Check(napi_status status) {
    if (status != napi_ok) throw BridgeProblem(ErrorCode::InternalError, "NAPI_CALL_FAILED");
}
napi_value Text(napi_env env, const std::string& text) {
    napi_value value{};
    Check(napi_create_string_utf8(env, text.c_str(), text.size(), &value));
    return value;
}
napi_value Object(napi_env env) {
    napi_value value{}; Check(napi_create_object(env, &value)); return value;
}
napi_value Array(napi_env env) {
    napi_value value{}; Check(napi_create_array(env, &value)); return value;
}
void Put(napi_env env, napi_value object, const char* key, napi_value value) {
    Check(napi_set_named_property(env, object, key, value));
}
void PutText(napi_env env, napi_value object, const char* key, const std::string& value) {
    Put(env, object, key, Text(env, value));
}
void PutNumber(napi_env env, napi_value object, const char* key, double value) {
    napi_value field{}; Check(napi_create_double(env, value, &field)); Put(env, object, key, field);
}
void PutBool(napi_env env, napi_value object, const char* key, bool value) {
    napi_value field{}; Check(napi_get_boolean(env, value, &field)); Put(env, object, key, field);
}
napi_value GetObject(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value args[2]{};
    Check(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
    napi_valuetype type{};
    if (argc != 1 || napi_typeof(env, args[0], &type) != napi_ok || type != napi_object)
        throw BridgeProblem(ErrorCode::InvalidRequest, "EXPECTED_OBJECT");
    napi_value nullValue{}; bool isNull{};
    Check(napi_get_null(env, &nullValue));
    Check(napi_strict_equals(env, args[0], nullValue, &isNull));
    bool isArray{}; Check(napi_is_array(env, args[0], &isArray));
    if (isNull || isArray) throw BridgeProblem(ErrorCode::InvalidRequest, "EXPECTED_OBJECT");
    return args[0];
}
std::string ReadString(napi_env env, napi_value value) {
    napi_valuetype type{};
    Check(napi_typeof(env, value, &type));
    if (type != napi_string) throw BridgeProblem(ErrorCode::InvalidRequest, "EXPECTED_STRING");
    size_t length{}; Check(napi_get_value_string_utf8(env, value, nullptr, 0, &length));
    if (length == 0 || length > 4096) throw BridgeProblem(ErrorCode::InvalidRequest, "STRING_RANGE");
    std::vector<char> buffer(length + 1);
    size_t copied{};
    Check(napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied));
    return std::string(buffer.data(), copied);
}
std::string FieldString(napi_env env, napi_value object, const char* key) {
    bool present{}; Check(napi_has_named_property(env, object, key, &present));
    if (!present) throw BridgeProblem(ErrorCode::InvalidRequest, "MISSING_FIELD");
    napi_value value{}; Check(napi_get_named_property(env, object, key, &value));
    return ReadString(env, value);
}
void ValidateSchema(napi_env env, napi_value object) {
    bool present{}; Check(napi_has_named_property(env, object, "schemaVersion", &present));
    if (!present) throw BridgeProblem(ErrorCode::InvalidRequest, "MISSING_SCHEMA");
    napi_value value{}; Check(napi_get_named_property(env, object, "schemaVersion", &value));
    napi_valuetype type{}; Check(napi_typeof(env, value, &type));
    if (type != napi_number) throw BridgeProblem(ErrorCode::InvalidRequest, "SCHEMA_TYPE");
    double version{}; Check(napi_get_value_double(env, value, &version));
    if (!std::isfinite(version) || std::floor(version) != version)
        throw BridgeProblem(ErrorCode::InvalidRequest, "SCHEMA_RANGE");
    if (version != kSchemaVersion) throw BridgeProblem(ErrorCode::ProtocolIncompatible, "SCHEMA_VERSION");
}
napi_value MakeError(napi_env env, ErrorCode code, const char* reason) {
    napi_value error{};
    auto name = Text(env, ErrorCodeName(code));
    Check(napi_create_error(env, name, Text(env, ErrorCodeName(code)), &error));
    PutText(env, error, "reason", reason);
    PutText(env, error, "module", "NativeBridge");
    PutText(env, error, "stage", "preparing");
    PutBool(env, error, "retryable", false);
    PutText(env, error, "traceId", "native-migration");
    PutText(env, error, "messageKey", std::string("errors.") + ErrorCodeName(code));
    return error;
}
template <class Fn> napi_value Boundary(napi_env env, Fn fn) noexcept {
    try { return fn(); }
    catch (const BridgeProblem& error) {
        try { Check(napi_throw(env, MakeError(env, error.code, error.what()))); }
        catch (...) { (void)napi_throw_error(env, "INTERNAL_ERROR", "Native boundary failure"); }
    }
    catch (const std::bad_alloc&) {
        (void)napi_throw_error(env, "RESOURCE_LIMIT_EXCEEDED", "Native allocation failed");
    }
    catch (...) { (void)napi_throw_error(env, "INTERNAL_ERROR", "Native boundary failure"); }
    return nullptr;
}
enum class WorkKind { Capabilities, ConvertMissing, Unsupported, ControlMissing, Release };
struct Work {
    napi_async_work handle{};
    napi_deferred deferred{};
    WorkKind kind{};
    std::string taskId, attemptId;
    ErrorCode error{ErrorCode::EngineMissing};
    const char* reason{"ENGINE_NOT_LINKED"};
    std::chrono::steady_clock::time_point started;
    double elapsedMs{};
};
void Run(napi_env, void* data) noexcept {
    // Only C++ data on worker thread; no napi_env/napi_value access.
    auto* work = static_cast<Work*>(data);
    work->elapsedMs = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - work->started).count();
}
napi_value CapabilityResult(napi_env env) {
    auto result = Object(env);
    PutNumber(env, result, "schemaVersion", kSchemaVersion);
    PutBool(env, result, "offlineOnly", true);
#if defined(__aarch64__)
    PutText(env, result, "abi", "arm64-v8a");
#elif defined(__x86_64__)
    PutText(env, result, "abi", "x86_64");
#else
    PutText(env, result, "abi", "unverified");
#endif
    PutText(env, result, "configVersion", kConfigVersion);
    // The experimental image engine is linked, but no route has release evidence.
    Put(env, result, "engines", Array(env));
    Put(env, result, "routes", Array(env));
    return result;
}
napi_value MissingResult(napi_env env, const Work& work) {
    auto result = Object(env);
    PutNumber(env, result, "schemaVersion", kSchemaVersion);
    PutText(env, result, "taskId", work.taskId);
    PutText(env, result, "attemptId", work.attemptId);
    PutText(env, result, "status", "failed");
    Put(env, result, "error", MakeError(env, work.error, work.reason));
    Put(env, result, "warnings", Array(env));
    Put(env, result, "outputs", Array(env));
    Put(env, result, "engines", Array(env));
    auto validation = Object(env);
    PutText(env, validation, "state", "not_evaluated");
    PutText(env, validation, "validatorVersion", "not-linked");
    Put(env, validation, "evidenceRefs", Array(env));
    Put(env, result, "validation", validation);
    PutNumber(env, result, "elapsedMs", work.elapsedMs);
    PutNumber(env, result, "nativePeakBytes", 0);
    PutNumber(env, result, "tempPeakBytes", 0);
    return result;
}
void Complete(napi_env env, napi_status status, void* data) noexcept {
    std::unique_ptr<Work> work(static_cast<Work*>(data));
    try {
        if (status != napi_ok) {
            Check(napi_reject_deferred(env, work->deferred,
                MakeError(env, ErrorCode::InternalError, "ASYNC_WORK_FAILED")));
        } else if (work->kind == WorkKind::Unsupported) {
            Check(napi_reject_deferred(env, work->deferred, MakeError(env, work->error, work->reason)));
        } else {
            napi_value result{};
            switch (work->kind) {
                case WorkKind::Capabilities: result = CapabilityResult(env); break;
                case WorkKind::ConvertMissing: result = MissingResult(env, *work); break;
                case WorkKind::ControlMissing:
                    result = Object(env);
                    PutText(env, result, "taskId", work->taskId);
                    PutText(env, result, "attemptId", work->attemptId);
                    PutText(env, result, "state", "not_found");
                    break;
                default: Check(napi_get_undefined(env, &result)); break;
            }
            Check(napi_resolve_deferred(env, work->deferred, result));
        }
    } catch (...) {
        // Reject the original promise instead of leaving it pending. During environment
        // teardown/allocation failure NAPI may be unavailable: cleanup is best effort.
        bool pending{};
        napi_value error{};
        if (napi_is_exception_pending(env, &pending) == napi_ok && pending)
            (void)napi_get_and_clear_last_exception(env, &error);
        if (!error) {
            try { error = MakeError(env, ErrorCode::InternalError, "ASYNC_COMPLETION_FAILED"); }
            catch (...) { (void)napi_get_undefined(env, &error); }
        }
        if (error) (void)napi_reject_deferred(env, work->deferred, error);
    }
    (void)napi_delete_async_work(env, work->handle);
}
napi_value Queue(napi_env env, std::unique_ptr<Work> work) {
    napi_value promise{};
    Check(napi_create_promise(env, &work->deferred, &promise));
    work->started = std::chrono::steady_clock::now();
    try {
        Check(napi_create_async_work(env, nullptr, Text(env, "DocumentNativeBridge"), Run, Complete,
            work.get(), &work->handle));
        Check(napi_queue_async_work(env, work->handle));
    } catch (...) {
        if (work->handle) (void)napi_delete_async_work(env, work->handle);
        Check(napi_reject_deferred(env, work->deferred,
            MakeError(env, ErrorCode::InternalError, "ASYNC_QUEUE_FAILED")));
        return promise;
    }
    work.release();
    return promise;
}
napi_value GetCapabilities(napi_env env, napi_callback_info info) {
    return Boundary(env, [&] {
        auto request = GetObject(env, info);
        ValidateSchema(env, request);
        (void)FieldString(env, request, "sessionId");
        if (FieldString(env, request, "configVersion") != kConfigVersion)
            throw BridgeProblem(ErrorCode::ConfigInvalid, "CONFIG_VERSION_MISMATCH");
        auto work = std::make_unique<Work>();
        work->kind = WorkKind::Capabilities;
        return Queue(env, std::move(work));
    });
}
napi_value Execute(napi_env env, napi_callback_info info) {
    return Boundary(env, [&] {
        auto request = GetObject(env, info); ValidateSchema(env, request);
        auto work = std::make_unique<Work>(); work->kind = WorkKind::ConvertMissing;
        work->taskId = FieldString(env, request, "taskId");
        work->attemptId = FieldString(env, request, "attemptId");
        (void)FieldString(env, request, "targetFormatId");
        // Full decoder/authorization/protection checks are required before any real engine is enabled.
        return Queue(env, std::move(work));
    });
}
napi_value Unsupported(napi_env env, napi_callback_info) {
    return Boundary(env, [&] {
        auto work = std::make_unique<Work>(); work->kind = WorkKind::Unsupported;
        work->error = ErrorCode::UnsupportedFeature; work->reason = "MIGRATED_CONTRACT_NOT_IMPLEMENTED";
        return Queue(env, std::move(work));
    });
}
napi_value Control(napi_env env, napi_callback_info info) {
    return Boundary(env, [&] {
        size_t argc = 3; napi_value args[3]{};
        Check(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
        if (argc != 2) throw BridgeProblem(ErrorCode::InvalidRequest, "CONTROL_ARGUMENTS");
        auto work = std::make_unique<Work>(); work->kind = WorkKind::ControlMissing;
        work->taskId = ReadString(env, args[0]); work->attemptId = ReadString(env, args[1]);
        return Queue(env, std::move(work));
    });
}
napi_value Subscribe(napi_env env, napi_callback_info) {
    return Boundary(env, [&]() -> napi_value {
        throw BridgeProblem(ErrorCode::EngineMissing, "NO_EXECUTING_ENGINE");
    });
}
napi_value Unsubscribe(napi_env env, napi_callback_info) {
    return Boundary(env, [&] { napi_value value{}; Check(napi_get_boolean(env, false, &value)); return value; });
}
napi_value Release(napi_env env, napi_callback_info) {
    return Boundary(env, [&] { auto work = std::make_unique<Work>(); work->kind = WorkKind::Release;
        return Queue(env, std::move(work)); });
}
} // namespace
napi_value RegisterNativeBridge(napi_env env, napi_value exports) {
    return Boundary(env, [&] {
        napi_property_descriptor descriptors[] = {
#ifdef HDM_PRODUCTION_NATIVE
            {"initializeSession", nullptr, ProductionInitialize, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"registerWorkspace", nullptr, ProductionRegister, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"getCapabilities", nullptr, GetCapabilities, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"probeInputs", nullptr, ProductionProbe, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"execute", nullptr, ProductionExecute, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"subscribeProgress", nullptr, ProductionSubscribe, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"unsubscribeProgress", nullptr, ProductionUnsubscribe, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"cancel", nullptr, ProductionCancel, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"pause", nullptr, ProductionPause, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"resume", nullptr, ProductionResume, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"releaseTask", nullptr, ProductionReleaseTask, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"releaseArtifact", nullptr, ProductionReleaseArtifact, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"shutdown", nullptr, ProductionShutdown, nullptr, nullptr, nullptr, napi_default, nullptr}
#else
            {"initializeSession", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"registerWorkspace", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"getCapabilities", nullptr, GetCapabilities, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"probeInputs", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"execute", nullptr, Execute, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"subscribeProgress", nullptr, Subscribe, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"unsubscribeProgress", nullptr, Unsubscribe, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"cancel", nullptr, Control, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"pause", nullptr, Control, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"resume", nullptr, Control, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"releaseTask", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"releaseArtifact", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
            {"shutdown", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr}
#endif
        };
        Check(napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors));
        return exports;
    });
}
} // namespace hdm
