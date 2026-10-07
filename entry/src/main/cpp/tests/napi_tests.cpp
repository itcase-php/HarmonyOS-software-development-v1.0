#include "../napi/native_bridge.h"
#include "../napi/result_serializer.h"
#include "../production/route_policy.h"
#include "../generated/registry_metadata.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

struct MockDeferred { enum State { Pending, Resolved, Rejected } state{Pending}; napi_value result{}; };
struct MockValue {
    napi_valuetype type{napi_undefined};
    std::string text;
    double number{};
    bool boolean{}, array{};
    std::map<std::string, napi_value> fields;
    std::vector<napi_value> elements;
    napi_deferred deferred{};
};
struct MockInfo { std::vector<napi_value> args; };
struct MockWork {
    napi_async_execute_callback execute{};
    napi_async_complete_callback complete{};
    void* data{};
    bool queued{}, deleted{};
};
struct MockEnv {
    std::vector<std::unique_ptr<MockValue>> values;
    std::vector<std::unique_ptr<MockDeferred>> deferreds;
    std::vector<std::unique_ptr<MockWork>> works;
    std::map<std::string, napi_callback> methods;
    napi_value exception{};
    std::string failNext, allocateNext;
    bool inWorker{}, workerApiAccess{};
    size_t deleteCount{};
    napi_value value(napi_valuetype type) {
        values.push_back(std::make_unique<MockValue>());
        values.back()->type = type;
        return values.back().get();
    }
    bool allow(const char* operation) {
        if (inWorker) { workerApiAccess = true; return false; }
        if (allocateNext == operation) { allocateNext.clear(); throw std::bad_alloc(); }
        if (failNext == operation) { failNext.clear(); return false; }
        return true;
    }
};
#define CHECK_API(name) if (!env->allow(#name)) return napi_generic_failure
napi_status napi_create_string_utf8(napi_env env, const char* text, size_t size, napi_value* result) {
    CHECK_API(napi_create_string_utf8); *result = env->value(napi_string); (*result)->text.assign(text, size); return napi_ok;
}
napi_status napi_create_object(napi_env env, napi_value* result) {
    CHECK_API(napi_create_object); *result = env->value(napi_object); return napi_ok;
}
napi_status napi_create_array(napi_env env, napi_value* result) {
    CHECK_API(napi_create_array); *result = env->value(napi_object); (*result)->array = true; return napi_ok;
}
napi_status napi_create_double(napi_env env, double number, napi_value* result) {
    CHECK_API(napi_create_double); *result = env->value(napi_number); (*result)->number = number; return napi_ok;
}
napi_status napi_get_boolean(napi_env env, bool boolean, napi_value* result) {
    CHECK_API(napi_get_boolean); *result = env->value(napi_boolean); (*result)->boolean = boolean; return napi_ok;
}
napi_status napi_set_named_property(napi_env env, napi_value object, const char* key, napi_value value) {
    CHECK_API(napi_set_named_property); object->fields[key] = value; return napi_ok;
}
napi_status napi_set_element(napi_env env, napi_value array, std::uint32_t index, napi_value value) {
    CHECK_API(napi_set_element);
    if (!array->array || index > 100) return napi_generic_failure;
    if (array->elements.size() <= index) array->elements.resize(index + 1);
    array->elements[index] = value; return napi_ok;
}
napi_status napi_has_named_property(napi_env env, napi_value object, const char* key, bool* result) {
    CHECK_API(napi_has_named_property); *result = object->fields.count(key) != 0; return napi_ok;
}
napi_status napi_get_named_property(napi_env env, napi_value object, const char* key, napi_value* result) {
    CHECK_API(napi_get_named_property); *result = object->fields.at(key); return napi_ok;
}
napi_status napi_get_cb_info(napi_env env, napi_callback_info info, size_t* count, napi_value* args, napi_value*, void**) {
    CHECK_API(napi_get_cb_info); const auto copied = std::min(*count, info->args.size());
    std::copy_n(info->args.begin(), copied, args); *count = copied; return napi_ok;
}
napi_status napi_typeof(napi_env env, napi_value value, napi_valuetype* type) {
    CHECK_API(napi_typeof); if (!value) return napi_generic_failure; *type = value->type; return napi_ok;
}
napi_status napi_get_null(napi_env env, napi_value* result) {
    CHECK_API(napi_get_null); *result = env->value(napi_null); return napi_ok;
}
napi_status napi_get_undefined(napi_env env, napi_value* result) {
    CHECK_API(napi_get_undefined); *result = env->value(napi_undefined); return napi_ok;
}
napi_status napi_strict_equals(napi_env env, napi_value a, napi_value b, bool* equal) {
    CHECK_API(napi_strict_equals); *equal = a == b || (a->type == napi_null && b->type == napi_null); return napi_ok;
}
napi_status napi_is_array(napi_env env, napi_value value, bool* result) {
    CHECK_API(napi_is_array); *result = value->array; return napi_ok;
}
napi_status napi_get_value_string_utf8(napi_env env, napi_value value, char* buffer, size_t capacity, size_t* copied) {
    CHECK_API(napi_get_value_string_utf8);
    if (!buffer) { *copied = value->text.size(); return napi_ok; }
    *copied = std::min(value->text.size(), capacity ? capacity - 1 : 0);
    if (capacity) { std::memcpy(buffer, value->text.data(), *copied); buffer[*copied] = '\0'; }
    return napi_ok;
}
napi_status napi_get_value_double(napi_env env, napi_value value, double* result) {
    CHECK_API(napi_get_value_double); *result = value->number; return napi_ok;
}
napi_status napi_create_error(napi_env env, napi_value code, napi_value message, napi_value* result) {
    CHECK_API(napi_create_error); *result = env->value(napi_object);
    (*result)->fields["code"] = code; (*result)->fields["message"] = message; return napi_ok;
}
napi_status napi_throw(napi_env env, napi_value value) {
    CHECK_API(napi_throw); env->exception = value; return napi_ok;
}
napi_status napi_throw_error(napi_env env, const char* code, const char* message) {
    CHECK_API(napi_throw_error); auto error = env->value(napi_object);
    auto c = env->value(napi_string), m = env->value(napi_string);
    c->text = code; m->text = message; error->fields["code"] = c; error->fields["message"] = m;
    env->exception = error; return napi_ok;
}
napi_status napi_is_exception_pending(napi_env env, bool* pending) {
    CHECK_API(napi_is_exception_pending); *pending = env->exception != nullptr; return napi_ok;
}
napi_status napi_get_and_clear_last_exception(napi_env env, napi_value* result) {
    CHECK_API(napi_get_and_clear_last_exception); *result = env->exception; env->exception = nullptr; return napi_ok;
}
napi_status napi_create_promise(napi_env env, napi_deferred* deferred, napi_value* result) {
    CHECK_API(napi_create_promise); env->deferreds.push_back(std::make_unique<MockDeferred>());
    *deferred = env->deferreds.back().get(); *result = env->value(napi_object); (*result)->deferred = *deferred; return napi_ok;
}
napi_status napi_create_async_work(napi_env env, napi_value, napi_value, napi_async_execute_callback execute,
    napi_async_complete_callback complete, void* data, napi_async_work* result) {
    CHECK_API(napi_create_async_work); env->works.push_back(std::make_unique<MockWork>()); *result = env->works.back().get();
    (*result)->execute = execute; (*result)->complete = complete; (*result)->data = data; return napi_ok;
}
napi_status napi_queue_async_work(napi_env env, napi_async_work work) {
    CHECK_API(napi_queue_async_work); work->queued = true; return napi_ok;
}
napi_status napi_delete_async_work(napi_env env, napi_async_work work) {
    CHECK_API(napi_delete_async_work);
    if (work->deleted) throw std::logic_error("async work deleted twice");
    work->deleted = true; ++env->deleteCount; return napi_ok;
}
napi_status napi_resolve_deferred(napi_env env, napi_deferred deferred, napi_value value) {
    CHECK_API(napi_resolve_deferred);
    if (deferred->state != MockDeferred::Pending) throw std::logic_error("promise settled twice");
    deferred->state = MockDeferred::Resolved; deferred->result = value; return napi_ok;
}
napi_status napi_reject_deferred(napi_env env, napi_deferred deferred, napi_value value) {
    CHECK_API(napi_reject_deferred);
    if (deferred->state != MockDeferred::Pending) throw std::logic_error("promise settled twice");
    deferred->state = MockDeferred::Rejected; deferred->result = value; return napi_ok;
}
napi_status napi_define_properties(napi_env env, napi_value, size_t count, const napi_property_descriptor* descriptors) {
    CHECK_API(napi_define_properties);
    for (size_t i = 0; i < count; ++i) env->methods.emplace(descriptors[i].utf8name, descriptors[i].method);
    return napi_ok;
}
#undef CHECK_API

#ifdef HDM_PRODUCTION_NATIVE
namespace hdm {
#define HDM_NAPI_TEST_STUB(name) napi_value name(napi_env, napi_callback_info) { return nullptr; }
HDM_NAPI_TEST_STUB(ProductionInitialize)
HDM_NAPI_TEST_STUB(ProductionRegister)
HDM_NAPI_TEST_STUB(ProductionProbe)
HDM_NAPI_TEST_STUB(ProductionExecute)
HDM_NAPI_TEST_STUB(ProductionSubscribe)
HDM_NAPI_TEST_STUB(ProductionUnsubscribe)
HDM_NAPI_TEST_STUB(ProductionCancel)
HDM_NAPI_TEST_STUB(ProductionPause)
HDM_NAPI_TEST_STUB(ProductionResume)
HDM_NAPI_TEST_STUB(ProductionReleaseTask)
HDM_NAPI_TEST_STUB(ProductionReleaseArtifact)
HDM_NAPI_TEST_STUB(ProductionCopyArtifact)
HDM_NAPI_TEST_STUB(ProductionShutdown)
#undef HDM_NAPI_TEST_STUB
}
#endif

namespace {
void Require(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
std::string Field(napi_value value, const char* key) { return value->fields.at(key)->text; }
struct Fixture {
    MockEnv env;
    Fixture() {
        auto exports = env.value(napi_object);
        Require(hdm::RegisterNativeBridge(&env, exports) == exports, "register failed");
    }
    napi_value text(const std::string& value) { auto v = env.value(napi_string); v->text = value; return v; }
    napi_value number(double value) { auto v = env.value(napi_number); v->number = value; return v; }
    napi_value request() {
        auto v = env.value(napi_object); v->fields["schemaVersion"] = number(1);
        v->fields["sessionId"] = text("session"); v->fields["configVersion"] = text(hdm::kConfigVersion);
        v->fields["taskId"] = text("task"); v->fields["attemptId"] = text("attempt");
        v->fields["targetFormatId"] = text("pdf"); return v;
    }
    napi_value call(const char* method, std::vector<napi_value> args = {}) {
        MockInfo info{std::move(args)}; return env.methods.at(method)(&env, &info);
    }
    void flush(napi_status status = napi_ok) {
        // Simulate distinct worker/completion phases and reject worker NAPI use.
        for (auto& owned : env.works) {
            auto* work = owned.get(); if (!work->queued || work->deleted) continue;
            env.inWorker = true; work->execute(&env, work->data); env.inWorker = false;
            work->complete(&env, status, work->data);
            Require(work->deleted, "completion leaked async work");
        }
        Require(!env.workerApiAccess, "NAPI called during worker phase");
    }
    void error(const char* code, const char* reason) {
        Require(env.exception != nullptr, "expected synchronous exception");
        Require(Field(env.exception, "code") == code, "unexpected error code");
        Require(Field(env.exception, "reason") == reason, "unexpected error reason");
    }
};
void Exports() {
    Fixture f;
    const std::set<std::string> expected{"initializeSession", "registerWorkspace", "getCapabilities", "probeInputs",
        "execute", "subscribeProgress", "unsubscribeProgress", "cancel", "pause", "resume", "releaseTask", "releaseArtifact", "copyArtifactToFd", "shutdown"};
    std::set<std::string> actual; for (const auto& entry : f.env.methods) actual.insert(entry.first);
    Require(actual == expected, "14 API contract changed");
    auto promise = f.call("getCapabilities", {f.request()});
    Require(promise->deferred->state == MockDeferred::Pending, "work resolved before completion");
    f.flush(); auto result = promise->deferred->result;
    Require(promise->deferred->state == MockDeferred::Resolved, "capabilities rejected");
    Require(result->fields.at("offlineOnly")->boolean, "offline mode changed");
#ifdef HDM_PRODUCTION_NATIVE
    auto engines = result->fields.at("engines");
    auto routes = result->fields.at("routes");
    Require(engines->array && engines->elements.size()==1, "linked experimental engine missing");
    const auto stamp = Field(engines->elements[0], "buildHash");
    Require(Field(engines->elements[0], "engineId")=="image" && stamp.size()==64 &&
        stamp!=std::string(64,'0') && stamp!=hdm::kMatrixHash, "engine build stamp is not a build manifest digest");
    Require(routes->array && routes->elements.size() == 1, "experimental route diagnostic missing");
    auto route = routes->elements[0];
    Require(Field(route, "routeId") == hdm::kJpegPdfRouteId &&
        Field(route, "availability") == "experimental" &&
        Field(route, "reason") == (hdm::production::IsDebugRouteExecutable(hdm::kJpegPdfRouteId) ?
            "NATIVE_DEBUG_ROUTE_ENABLED" : "NATIVE_ROUTE_UNAVAILABLE") &&
        Field(route, "validationProfileId") == hdm::kJpegPdfValidationProfile,
        "route diagnostic identity changed");
#ifdef HDM_NATIVE_DEBUG
    Require(hdm::production::IsDebugRouteExecutable("jpeg-pdf"), "Debug JPEG whitelist blocked");
#else
    Require(!hdm::production::IsDebugRouteExecutable("jpeg-pdf"), "Release enabled experimental route");
#endif
    Require(!hdm::production::IsDebugRouteExecutable("docx-pdf") &&
        !hdm::production::IsDebugRouteExecutable("pptx-pdf") &&
        !hdm::production::IsDebugRouteExecutable("png-pdf"), "Debug enabled an unapproved route");
    Require(route->fields.count("releaseEvidenceId") == 0 &&
        route->fields.count("from") == 0 &&
        !route->fields.at("supportsPause")->boolean &&
        route->fields.at("decoderIds")->elements.size() == 1 &&
        route->fields.at("encoderIds")->elements.size() == 1,
        "planned diagnostic advertised release capability");
    Require(route->fields.at("decoderIds")->elements[0]->text ==
        "jpeg-baseline-sof0-gray-rgb-exif-icc-v2" &&
        route->fields.at("encoderIds")->elements[0]->text == "pdf-dct-single-page-icc-v2" &&
        Field(route, "inputSubsetId") == "jpeg-baseline-sof0-jfif-exif-icc-v2",
        "linked subset diagnostic changed");
#else
    for (const char* field : {"engines", "routes"}) Require(result->fields.at(field)->array && result->fields.at(field)->fields.empty(), "placeholder available");
#endif
}
void Schema() {
    for (const auto& item : std::vector<std::pair<double, std::string>>{{2, "SCHEMA_VERSION"}, {1.5, "SCHEMA_RANGE"},
            {std::numeric_limits<double>::quiet_NaN(), "SCHEMA_RANGE"}, {std::numeric_limits<double>::infinity(), "SCHEMA_RANGE"}}) {
        Fixture f; auto request = f.request(); request->fields["schemaVersion"] = f.number(item.first);
        Require(f.call("getCapabilities", {request}) == nullptr, "invalid schema accepted");
        f.error(item.first == 2 ? "PROTOCOL_INCOMPATIBLE" : "INVALID_REQUEST", item.second.c_str());
    }
    for (int kind = 0; kind < 7; ++kind) {
        Fixture f; auto request = f.request(); const char* reason = "EXPECTED_OBJECT";
        std::vector<napi_value> args{request};
        if (kind == 0) args.clear();
        if (kind == 1) args.push_back(request);
        if (kind == 2) args[0] = f.env.value(napi_null);
        if (kind == 3) request->array = true;
        if (kind == 4) { request->fields.erase("schemaVersion"); reason = "MISSING_SCHEMA"; }
        if (kind == 5) { request->fields["schemaVersion"] = f.text("1"); reason = "SCHEMA_TYPE"; }
        if (kind == 6) { request->fields.erase("sessionId"); reason = "MISSING_FIELD"; }
        Require(f.call("getCapabilities", args) == nullptr, "invalid request accepted"); f.error("INVALID_REQUEST", reason);
    }
    Fixture f; auto request = f.request(); request->fields["configVersion"] = f.text("mismatch");
    f.call("getCapabilities", {request}); f.error("CONFIG_INVALID", "CONFIG_VERSION_MISMATCH");
}
void Unsupported() {
    for (const char* method : {"initializeSession", "registerWorkspace", "probeInputs"}) {
        Fixture f; auto promise = f.call(method, {f.request()}); f.flush();
        Require(promise->deferred->state == MockDeferred::Rejected, "placeholder claimed success");
        Require(Field(promise->deferred->result, "code") == "UNSUPPORTED_FEATURE", "unsupported error changed");
    }
}
void Missing() {
    Fixture f; auto promise = f.call("execute", {f.request()}); f.flush(); auto result = promise->deferred->result;
    Require(promise->deferred->state == MockDeferred::Resolved && Field(result, "status") == "failed", "missing converter succeeded");
    Require(Field(result->fields.at("error"), "code") == "ENGINE_MISSING", "missing converter error changed");
    Require(result->fields.at("outputs")->fields.empty(), "missing converter emitted output");
    Require(Field(result->fields.at("validation"), "state") == "not_evaluated", "fake validation");
    Require(result->fields.count("fidelity") == 0, "fake fidelity evidence");
    Require(Field(result, "taskId") == "task" && Field(result, "attemptId") == "attempt", "task identity lost");
}
void Controls() {
    for (const char* method : {"cancel", "pause", "resume"}) {
        Fixture f; auto promise = f.call(method, {f.text("task"), f.text("attempt")}); f.flush();
        Require(Field(promise->deferred->result, "state") == "not_found", "control changed");
        f.call(method, {f.text("task")}); f.error("INVALID_REQUEST", "CONTROL_ARGUMENTS");
    }
    Fixture f; f.call("subscribeProgress"); f.error("ENGINE_MISSING", "NO_EXECUTING_ENGINE");
    f.env.exception = nullptr; Require(!f.call("unsubscribeProgress")->boolean, "unsubscribe changed");
    for (const char* method : {"releaseTask", "releaseArtifact", "shutdown"}) {
        auto promise = f.call(method); f.flush(); Require(promise->deferred->state == MockDeferred::Resolved, "release rejected");
        Require(promise->deferred->result->type == napi_undefined, "release result changed");
    }
}
void Queue() {
    for (const char* operation : {"napi_create_async_work", "napi_queue_async_work"}) {
        Fixture f; f.env.failNext = operation; auto promise = f.call("getCapabilities", {f.request()});
        Require(promise && promise->deferred->state == MockDeferred::Rejected, "queue failure left pending");
        Require(Field(promise->deferred->result, "reason") == "ASYNC_QUEUE_FAILED", "queue diagnostic lost");
        Require(f.env.deleteCount == (std::string(operation) == "napi_queue_async_work" ? 1U : 0U), "queue ownership leaked");
        f.flush();
    }
}
void Completion() {
    for (const char* operation : {"napi_create_object", "napi_resolve_deferred", "napi_set_named_property"}) {
        Fixture f; auto promise = f.call("getCapabilities", {f.request()}); f.env.failNext = operation; f.flush();
        Require(promise->deferred->state == MockDeferred::Rejected, "completion failure left pending");
        Require(Field(promise->deferred->result, "reason") == "ASYNC_COMPLETION_FAILED", "completion diagnostic lost");
        Require(f.env.deleteCount == 1, "completion ownership leaked");
    }
    Fixture f; auto promise = f.call("getCapabilities", {f.request()}); f.flush(napi_generic_failure);
    Require(promise->deferred->state == MockDeferred::Rejected, "async failure left pending");
    Require(Field(promise->deferred->result, "reason") == "ASYNC_WORK_FAILED", "async status lost");
}
void Reports() {
    Fixture fixture; hdm::ConvertResult input; input.schemaVersion=1;
    input.taskId="task"; input.attemptId="attempt";
    input.warnings.push_back({hdm::ErrorCode::FontMissing,"FONT_ABSENT","errors.FONT_MISSING",true,std::string("font-check")});
    hdm::FidelityReport report; report.schemaVersion=1;
    report.intent=hdm::Intent::LayoutPreserved; report.requestedTier=hdm::FidelityTier::Extreme;
    report.sourcePageCount=0; report.outputPageCount=1;
    report.metrics.push_back({"text", "ratio", "text-v1", hdm::MetricState::Measured, 0.0, 1.0, {"text-check"}});
    report.metrics.push_back({"visual", "ratio", "visual-v1", hdm::MetricState::Unavailable, {}, {}, {}});
    report.detectorVersion="report-v1"; report.fontSubstitutions={"source -> target"};
    report.unsupportedFeatures={"animation"}; report.degradations={"static"}; report.evidenceRefs={"report-check"};
    input.fidelity=report;
    input.outputs.push_back({"artifact", "primary", "pdf", "artifact:ref", std::string(64,'a'), 10, 0});
    hdm::Status failure; failure.code=hdm::ErrorCode::OutputValidationFailed;
    failure.reason="PDF_STRUCTURE"; failure.module="pdf"; failure.stage=hdm::Stage::Validating;
    failure.traceId="trace-42"; failure.messageKey="errors.OUTPUT_VALIDATION_FAILED";
    failure.retryable=true; failure.detailKey="errors.pdf_structure"; input.error=failure;
    const auto output=hdm::SerializeConvertResult(&fixture.env,input);
    const auto error=output->fields.at("error");
    Require(Field(error,"module")=="pdf" && Field(error,"stage")=="validating" &&
        Field(error,"traceId")=="trace-42" && error->fields.at("retryable")->boolean &&
        Field(error,"detailKey")=="errors.pdf_structure", "native error diagnostics were overwritten");
    Require(output->fields.at("outputs")->elements[0]->fields.at("pageIndex")->number==0,
        "zero output page index was lost");
    const auto warnings=output->fields.at("warnings");
    Require(warnings->elements.size()==1,"native warnings were lost");
    const auto warning=warnings->elements[0];
    Require(Field(warning,"code")=="FONT_MISSING" && Field(warning,"evidenceRef")=="font-check" &&
        warning->fields.at("requiresManualReview")->boolean,"native warning evidence changed");
    Require(output->fields.count("fidelity")==1,"native fidelity was lost");
    const auto actual=output->fields.at("fidelity");
    Require(Field(actual,"intent")=="layout_preserved" && Field(actual,"requestedTier")=="extreme" &&
        actual->fields.count("achievedTier")==0,"native report invented a achieved tier");
    Require(actual->fields.at("sourcePageCount")->number==0 && actual->fields.at("outputPageCount")->number==1,
        "native report dropped zero page count");
    const auto metrics=actual->fields.at("metrics");
    Require(metrics->elements.size()==2 && metrics->elements[0]->fields.at("value")->number==0 &&
        metrics->elements[0]->fields.at("denominator")->number==1 &&
        metrics->elements[1]->fields.count("value")==0,"native report changed measurement state");
    input.fidelity.reset(); input.warnings.clear();
    const auto missing=hdm::SerializeConvertResult(&fixture.env,input);
    Require(missing->fields.count("fidelity")==0 && missing->fields.at("warnings")->elements.empty(),
        "missing evidence was fabricated");
}
void Boundary() {
    Fixture allocation; allocation.env.allocateNext = "napi_get_cb_info";
    Require(allocation.call("getCapabilities", {allocation.request()}) == nullptr, "bad_alloc escaped boundary");
    Require(Field(allocation.env.exception, "code") == "RESOURCE_LIMIT_EXCEEDED", "allocation diagnostic lost");
    Fixture fallback; fallback.env.failNext = "napi_create_error";
    Require(fallback.call("getCapabilities") == nullptr, "boundary failure escaped");
    Require(Field(fallback.env.exception, "code") == "INTERNAL_ERROR", "boundary fallback missing");
}
} // namespace
int main(int argc, char** argv) {
    try {
        Require(argc == 2, "choose a test case"); const std::string name = argv[1];
        const std::map<std::string, void (*)()> cases{{"exports", Exports}, {"schema", Schema}, {"unsupported", Unsupported},
            {"missing", Missing}, {"controls", Controls}, {"queue", Queue}, {"completion", Completion}, {"boundary", Boundary}, {"reports", Reports}};
        cases.at(name)(); std::cout << "PASS " << name << '\n'; return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
