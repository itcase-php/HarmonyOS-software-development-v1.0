#include "production_napi.h"
#include "result_serializer.h"
#include "bridge_problem.h"
#include "../production/runtime.h"
#include "../generated/registry_metadata.h"
#include <atomic>
#include <cmath>
#include <limits>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace hdm {
namespace {
void Check(napi_status status) {
    if (status!=napi_ok) throw BridgeProblem(ErrorCode::InternalError,"NAPI_CALL_FAILED");
}
napi_value Text(napi_env env, const std::string& value) {
    napi_value out{}; Check(napi_create_string_utf8(env,value.c_str(),value.size(),&out)); return out;
}
napi_value Object(napi_env env) { napi_value out{}; Check(napi_create_object(env,&out)); return out; }
napi_value Array(napi_env env) { napi_value out{}; Check(napi_create_array(env,&out)); return out; }
void Put(napi_env env,napi_value object,const char* key,napi_value value) {
    Check(napi_set_named_property(env,object,key,value));
}
void PutText(napi_env env,napi_value object,const char* key,const std::string& value) { Put(env,object,key,Text(env,value)); }
void PutNumber(napi_env env,napi_value object,const char* key,double value) {
    napi_value field{}; Check(napi_create_double(env,value,&field)); Put(env,object,key,field);
}
void PutBool(napi_env env,napi_value object,const char* key,bool value) {
    napi_value field{}; Check(napi_get_boolean(env,value,&field)); Put(env,object,key,field);
}
void Push(napi_env env,napi_value array,std::uint32_t index,napi_value value) {
    Check(napi_set_element(env,array,index,value));
}
napi_value Error(napi_env env,ErrorCode code,const char* reason) {
    napi_value error{};
    Check(napi_create_error(env,Text(env,ErrorCodeName(code)),Text(env,ErrorCodeName(code)),&error));
    PutText(env,error,"reason",reason); PutText(env,error,"module","NativeBridge");
    PutText(env,error,"stage","preparing"); PutText(env,error,"traceId","native-jpeg-pdf");
    PutText(env,error,"messageKey",std::string("errors.")+ErrorCodeName(code));
    PutBool(env,error,"retryable",false); return error;
}
template <typename Fn> napi_value Boundary(napi_env env,Fn fn) noexcept {
    try { return fn(); }
    catch (const BridgeProblem& error) {
        try { Check(napi_throw(env,Error(env,error.code,error.what()))); }
        catch (...) { (void)napi_throw_error(env,"INTERNAL_ERROR","Native boundary failure"); }
    } catch (const std::bad_alloc&) {
        (void)napi_throw_error(env,"RESOURCE_LIMIT_EXCEEDED","Native allocation failed");
    } catch (...) { (void)napi_throw_error(env,"INTERNAL_ERROR","Native boundary failure"); }
    return nullptr;
}
napi_value Arg(napi_env env,napi_callback_info info,std::size_t expected,std::size_t index=0) {
    std::size_t count=4; napi_value args[4]{};
    Check(napi_get_cb_info(env,info,&count,args,nullptr,nullptr));
    if (count!=expected || index>=count) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_ARGUMENTS");
    return args[index];
}
std::string String(napi_env env,napi_value value) {
    napi_valuetype type{}; Check(napi_typeof(env,value,&type));
    if (type!=napi_string) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_TEXT_TYPE");
    std::size_t length{}; Check(napi_get_value_string_utf8(env,value,nullptr,0,&length));
    if (!length || length>4096) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_TEXT_RANGE");
    std::vector<char> buffer(length+1); std::size_t copied{};
    Check(napi_get_value_string_utf8(env,value,buffer.data(),buffer.size(),&copied));
    const std::string text(buffer.data(),copied);
    if (copied!=length || text.find('\0')!=std::string::npos)
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_TEXT_INVALID");
    return text;
}
napi_value Field(napi_env env,napi_value object,const char* key) {
    napi_valuetype type{}; Check(napi_typeof(env,object,&type));
    bool array{}; Check(napi_is_array(env,object,&array));
    if (type!=napi_object || array) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_OBJECT_REQUIRED");
    bool present{}; Check(napi_has_named_property(env,object,key,&present));
    if (!present) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_FIELD_MISSING");
    napi_value value{}; Check(napi_get_named_property(env,object,key,&value)); return value;
}
std::string FieldString(napi_env env,napi_value object,const char* key) { return String(env,Field(env,object,key)); }
std::uint64_t Unsigned(napi_env env,napi_value value,std::uint64_t maximum) {
    napi_valuetype type{}; Check(napi_typeof(env,value,&type));
    if (type!=napi_number) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_NUMBER_TYPE");
    double number{}; Check(napi_get_value_double(env,value,&number));
    if (!std::isfinite(number) || number<0 || std::floor(number)!=number || number>maximum)
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_NUMBER_RANGE");
    return static_cast<std::uint64_t>(std::llround(number));
}
std::uint64_t FieldUnsigned(napi_env env,napi_value object,const char* key,std::uint64_t maximum) {
    return Unsigned(env,Field(env,object,key),maximum);
}
std::uint32_t Length(napi_env env,napi_value value,std::uint32_t maximum) {
    bool array{}; Check(napi_is_array(env,value,&array));
    if (!array) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_ARRAY_REQUIRED");
    std::uint32_t length{}; Check(napi_get_array_length(env,value,&length));
    if (length>maximum) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_ARRAY_LIMIT");
    return length;
}
napi_value Element(napi_env env,napi_value value,std::uint32_t index) {
    napi_value item{}; Check(napi_get_element(env,value,index,&item)); return item;
}
std::vector<std::string> Strings(napi_env env,napi_value value,std::uint32_t maximum) {
    const auto count=Length(env,value,maximum);
    std::vector<std::string> result; result.reserve(count);
    for (std::uint32_t i=0;i<count;++i) result.push_back(String(env,Element(env,value,i)));
    return result;
}
void Schema(napi_env env,napi_value value) {
    if (FieldUnsigned(env,value,"schemaVersion",std::numeric_limits<std::uint32_t>::max())!=kSchemaVersion)
        throw BridgeProblem(ErrorCode::ProtocolIncompatible,"NATIVE_SCHEMA_VERSION");
}
ResourceBudget Budget(napi_env env,napi_value value) {
    ResourceBudget result;
    result.maxInputBytes=FieldUnsigned(env,value,"maxInputBytes",100ULL*1024*1024);
    result.maxBatchBytes=FieldUnsigned(env,value,"maxBatchBytes",300ULL*1024*1024);
    result.maxNativeBytes=FieldUnsigned(env,value,"maxNativeBytes",192ULL*1024*1024);
    result.maxTempBytes=FieldUnsigned(env,value,"maxTempBytes",512ULL*1024*1024);
    result.maxPages=static_cast<std::uint32_t>(FieldUnsigned(env,value,"maxPages",300));
    result.maxPixels=static_cast<std::uint32_t>(FieldUnsigned(env,value,"maxPixels",16000000));
    result.maxThreads=static_cast<std::uint32_t>(FieldUnsigned(env,value,"maxThreads",2));
    result.timeoutMs=static_cast<std::uint32_t>(FieldUnsigned(env,value,"timeoutMs",180000));
    if (!result.maxInputBytes || !result.maxBatchBytes || !result.maxNativeBytes || !result.maxTempBytes ||
        !result.maxPages || !result.maxPixels || !result.maxThreads || !result.timeoutMs)
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_BUDGET_ZERO");
    return result;
}
std::vector<PreparedInput> Inputs(napi_env env,napi_value value) {
    const auto count=Length(env,value,100);
    if (!count) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_INPUT_EMPTY");
    std::vector<PreparedInput> inputs; inputs.reserve(count);
    for (std::uint32_t i=0;i<count;++i) {
        auto item=Element(env,value,i); PreparedInput input;
        input.fileId=FieldString(env,item,"fileId"); input.sourceFormatId=FieldString(env,item,"sourceFormatId");
        input.relativePath=FieldString(env,item,"relativePath"); input.sha256=FieldString(env,item,"sha256");
        input.byteSize=FieldUnsigned(env,item,"byteSize",100ULL*1024*1024);
        inputs.push_back(std::move(input));
    }
    return inputs;
}
Intent ParseIntent(const std::string& value) {
    if (value=="layout_preserved") return Intent::LayoutPreserved;
    if (value=="structured_rebuild") return Intent::StructuredRebuild;
    if (value=="content_only") return Intent::ContentOnly;
    throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_INTENT");
}
FidelityTier ParseTier(const std::string& value) {
    if (value=="extreme") return FidelityTier::Extreme;
    if (value=="standard") return FidelityTier::Standard;
    if (value=="compatible") return FidelityTier::Compatible;
    throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_TIER");
}
QualityMode ParseQuality(const std::string& value) {
    if (value=="fast") return QualityMode::Fast;
    if (value=="balanced") return QualityMode::Balanced;
    if (value=="high_fidelity") return QualityMode::HighFidelity;
    throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_QUALITY");
}
Operation ParseOperation(const std::string& value) {
    if (value=="images_to_pdf") return Operation::ImagesToPdf;
    if (value=="convert") return Operation::Convert;
    throw BridgeProblem(ErrorCode::UnsupportedFormat,"NATIVE_OPERATION_UNSUPPORTED");
}
ProbeRequest ParseProbe(napi_env env,napi_value value) {
    Schema(env,value); ProbeRequest request; request.schemaVersion=kSchemaVersion;
    request.sessionId=FieldString(env,value,"sessionId");
    request.workspaceRef=FieldString(env,value,"workspaceRef");
    request.inputs=Inputs(env,Field(env,value,"inputs"));
    request.resourceBudget=Budget(env,Field(env,value,"resourceBudget"));
    return request;
}
ConvertRequest ParseConvert(napi_env env,napi_value value) {
    Schema(env,value); ConvertRequest request; request.schemaVersion=kSchemaVersion;
    request.sessionId=FieldString(env,value,"sessionId");
    request.taskId=FieldString(env,value,"taskId"); request.attemptId=FieldString(env,value,"attemptId");
    request.workspaceRef=FieldString(env,value,"workspaceRef");
    request.targetFormatId=FieldString(env,value,"targetFormatId");
    request.operation=ParseOperation(FieldString(env,value,"operation"));
    request.qualityMode=ParseQuality(FieldString(env,value,"qualityMode"));
    request.intent=ParseIntent(FieldString(env,value,"intent"));
    request.inputs=Inputs(env,Field(env,value,"inputs"));
    request.resourceBudget=Budget(env,Field(env,value,"resourceBudget"));
    auto plan=Field(env,value,"plan");
    request.plan.routeId=FieldString(env,plan,"routeId");
    request.plan.configVersion=FieldString(env,plan,"configVersion");
    request.plan.configSha256=FieldString(env,plan,"configSha256");
    request.plan.policyVersion=FieldString(env,plan,"policyVersion");
    request.plan.intent=ParseIntent(FieldString(env,plan,"intent"));
    request.plan.minimumTier=ParseTier(FieldString(env,plan,"minimumTier"));
    request.plan.fallbackRouteIds=Strings(env,Field(env,plan,"fallbackRouteIds"),3);
    request.plan.allowedDegradations=Strings(env,Field(env,plan,"allowedDegradations"),10);
    auto steps=Field(env,plan,"steps"); const auto count=Length(env,steps,3);
    if (!count || request.plan.intent!=request.intent)
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_PLAN_INVALID");
    for (std::uint32_t i=0;i<count;++i) {
        auto item=Element(env,steps,i); PlanStep step;
        step.stepId=FieldString(env,item,"stepId");
        step.executorEngineId=FieldString(env,item,"executorEngineId");
        step.outputFormatId=FieldString(env,item,"outputFormatId");
        step.operation=ParseOperation(FieldString(env,item,"operation"));
        step.engineIds=Strings(env,Field(env,item,"engineIds"),10);
        step.inputFormatIds=Strings(env,Field(env,item,"inputFormatIds"),10);
        request.plan.steps.push_back(std::move(step));
    }
    auto options=Field(env,value,"options");
    napi_value keys{}; Check(napi_get_property_names(env,options,&keys));
    if (Length(env,keys,0)!=0) throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_OPTIONS_UNSUPPORTED");
    return request;
}

enum class Kind { Initialize,Register,Probe,Execute,Cancel,Pause,Resume,ReleaseTask,ReleaseArtifact,CopyArtifact,Shutdown };
struct Work {
    napi_async_work handle{}; napi_deferred deferred{};
    Kind kind{}; ErrorCode error{ErrorCode::Ok}; const char* reason{"NATIVE_WORK_FAILED"};
    SessionInit init; WorkspaceGrant grant; ProbeRequest probe; ConvertRequest convert;
    std::string first,second,textResult;
    int destinationFd{-1}; std::uint64_t exportBytes{}, copiedBytes{};
    production::ProbeResult probeResult; ConvertResult convertResult; ControlAck controlResult;
};
void Run(napi_env,void* data) noexcept {
    auto& work=*static_cast<Work*>(data);
    try {
        auto& runtime=production::SharedRuntime();
        switch (work.kind) {
            case Kind::Initialize: work.textResult=runtime.Initialize(work.init); break;
            case Kind::Register: work.textResult=runtime.Register(work.grant); break;
            case Kind::Probe: work.probeResult=runtime.Probe(work.probe); break;
            case Kind::Execute:
                if (std::string(kJpegPdfRouteStatus)!="available") {
                    work.convertResult.schemaVersion=kSchemaVersion;
                    work.convertResult.taskId=work.convert.taskId;
                    work.convertResult.attemptId=work.convert.attemptId;
                    Status blocked; blocked.code=ErrorCode::EngineMissing;
                    blocked.reason="NATIVE_ROUTE_PLANNED"; blocked.module="NativeBridge";
                    blocked.messageKey="errors.ENGINE_MISSING";
                    work.convertResult.error=blocked;
                } else work.convertResult=runtime.Execute(work.convert);
                break;
            case Kind::Cancel: work.controlResult=runtime.Control(work.first,work.second,"cancel"); break;
            case Kind::Pause: work.controlResult=runtime.Control(work.first,work.second,"pause"); break;
            case Kind::Resume: work.controlResult=runtime.Control(work.first,work.second,"resume"); break;
            case Kind::ReleaseTask: runtime.ReleaseTask(work.first,work.second); break;
            case Kind::ReleaseArtifact: runtime.ReleaseArtifact(work.first); break;
            case Kind::CopyArtifact:
                work.copiedBytes=runtime.CopyArtifactToFd(work.first,work.destinationFd,work.second,work.exportBytes); break;
            case Kind::Shutdown: runtime.Shutdown(); break;
        }
    } catch (const BridgeProblem& failure) { work.error=failure.code; work.reason="NATIVE_WORK_REJECTED"; }
    catch (const std::bad_alloc&) { work.error=ErrorCode::ResourceLimitExceeded; work.reason="NATIVE_ALLOCATION_FAILED"; }
    catch (...) { work.error=ErrorCode::InternalError; work.reason="NATIVE_WORK_FAILED"; }
}
const char* Protection(ProtectionState state) {
    switch (state) {
        case ProtectionState::None:return "none"; case ProtectionState::Drm:return "drm";
        case ProtectionState::Encrypted:return "encrypted"; case ProtectionState::Signed:return "signed";
        case ProtectionState::Unknown:return "unknown";
    }
    return "unknown";
}
napi_value SerializeProbe(napi_env env,const production::ProbeResult& result) {
    auto array=Array(env);
    for (std::uint32_t i=0;i<result.inputs.size();++i) {
        const auto& probe=result.inputs[i]; auto item=Object(env);
        PutText(env,item,"fileId",probe.fileId);
        if (probe.actualFormatId) PutText(env,item,"actualFormatId",*probe.actualFormatId);
        PutText(env,item,"protection",Protection(probe.protection));
        if (probe.pageCount) PutNumber(env,item,"pageCount",*probe.pageCount);
        PutBool(env,item,"needsDeepCheck",probe.needsDeepCheck); Push(env,array,i,item);
    }
    return array;
}
const char* ControlState(ControlAck::State state) {
    switch (state) {
        case ControlAck::State::Accepted:return "accepted"; case ControlAck::State::TooLate:return "too_late";
        case ControlAck::State::NotFound:return "not_found"; case ControlAck::State::Unsupported:return "unsupported";
    }
    return "not_found";
}
napi_value SerializeControl(napi_env env,const ControlAck& control) {
    auto result=Object(env); PutText(env,result,"taskId",control.taskId);
    PutText(env,result,"attemptId",control.attemptId);
    PutText(env,result,"state",ControlState(control.state)); return result;
}
struct Listener { std::string taskId; napi_ref ref{}; };
std::mutex listenersMutex;
std::unordered_map<std::string,Listener> listeners;
std::atomic<std::uint64_t> nextToken{1};
void DispatchProgress(napi_env env,const ConvertResult& result) {
    if (result.status!=ResultState::Success) return;
    std::vector<napi_ref> refs;
    {
        std::lock_guard<std::mutex> lock(listenersMutex);
        for (const auto& [token,entry]:listeners) if (entry.taskId==result.taskId) refs.push_back(entry.ref);
    }
    for (auto ref:refs) {
        try {
            napi_value listener{},global{};
            if (napi_get_reference_value(env,ref,&listener)!=napi_ok ||
                napi_get_global(env,&global)!=napi_ok) continue;
            auto event=Object(env); PutText(env,event,"taskId",result.taskId);
            PutText(env,event,"attemptId",result.attemptId); PutText(env,event,"stage","cleaning");
            PutNumber(env,event,"sequence",1); PutText(env,event,"unit","steps");
            PutNumber(env,event,"completedUnits",1); PutNumber(env,event,"totalUnits",1);
            PutNumber(env,event,"fraction",1);
            napi_value ignored{}; (void)napi_call_function(env,global,listener,1,&event,&ignored);
            bool pending{}; if (napi_is_exception_pending(env,&pending)==napi_ok && pending)
                (void)napi_get_and_clear_last_exception(env,&ignored);
        } catch (...) {
            napi_value ignored{}; bool pending{};
            if (napi_is_exception_pending(env,&pending)==napi_ok && pending)
                (void)napi_get_and_clear_last_exception(env,&ignored);
        }
    }
}
void Complete(napi_env env,napi_status status,void* data) noexcept {
    std::unique_ptr<Work> work(static_cast<Work*>(data));
    try {
        if (status!=napi_ok || work->error!=ErrorCode::Ok) {
            Check(napi_reject_deferred(env,work->deferred,Error(env,
                status!=napi_ok?ErrorCode::InternalError:work->error,
                status!=napi_ok?"ASYNC_WORK_FAILED":work->reason)));
        } else {
            napi_value value{};
            switch (work->kind) {
                case Kind::Initialize: case Kind::Register: value=Text(env,work->textResult); break;
                case Kind::Probe: value=SerializeProbe(env,work->probeResult); break;
                case Kind::Execute:
                    DispatchProgress(env,work->convertResult);
                    value=SerializeConvertResult(env,work->convertResult); break;
                case Kind::Cancel: case Kind::Pause: case Kind::Resume:
                    value=SerializeControl(env,work->controlResult); break;
                case Kind::CopyArtifact:
                    Check(napi_create_double(env,static_cast<double>(work->copiedBytes),&value)); break;
                default: Check(napi_get_undefined(env,&value)); break;
            }
            Check(napi_resolve_deferred(env,work->deferred,value));
        }
    } catch (...) {
        napi_value ignored{}; bool pending{};
        if (napi_is_exception_pending(env,&pending)==napi_ok && pending)
            (void)napi_get_and_clear_last_exception(env,&ignored);
        try { (void)napi_reject_deferred(env,work->deferred,
            Error(env,ErrorCode::InternalError,"NATIVE_COMPLETION_FAILED")); } catch (...) {}
    }
    (void)napi_delete_async_work(env,work->handle);
}
napi_value Queue(napi_env env,std::unique_ptr<Work> work) {
    napi_value promise{}; Check(napi_create_promise(env,&work->deferred,&promise));
    try {
        Check(napi_create_async_work(env,nullptr,Text(env,"JpegPdfProduction"),Run,Complete,work.get(),&work->handle));
        Check(napi_queue_async_work(env,work->handle));
    } catch (...) {
        if (work->handle) (void)napi_delete_async_work(env,work->handle);
        Check(napi_reject_deferred(env,work->deferred,Error(env,ErrorCode::InternalError,"NATIVE_QUEUE_FAILED")));
        return promise;
    }
    work.release(); return promise;
}
napi_value Control(napi_env env,napi_callback_info info,Kind kind) {
    return Boundary(env,[&] {
        auto first=Arg(env,info,2,0); auto second=Arg(env,info,2,1);
        auto work=std::make_unique<Work>(); work->kind=kind;
        work->first=String(env,first); work->second=String(env,second);
        return Queue(env,std::move(work));
    });
}
} // namespace

napi_value ProductionInitialize(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        auto value=Arg(env,info,1); Schema(env,value);
        auto work=std::make_unique<Work>(); work->kind=Kind::Initialize;
        work->init={kSchemaVersion,FieldString(env,value,"appSandboxRoot"),
            FieldString(env,value,"configVersion"),FieldString(env,value,"configSha256")};
        return Queue(env,std::move(work));
    });
}
napi_value ProductionRegister(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        auto value=Arg(env,info,1); auto work=std::make_unique<Work>(); work->kind=Kind::Register;
        work->grant={FieldString(env,value,"sessionId"),FieldString(env,value,"taskId"),
            FieldString(env,value,"attemptId"),FieldString(env,value,"relativeDirectory")};
        return Queue(env,std::move(work));
    });
}
napi_value ProductionProbe(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        auto work=std::make_unique<Work>(); work->kind=Kind::Probe;
        work->probe=ParseProbe(env,Arg(env,info,1)); return Queue(env,std::move(work));
    });
}
napi_value ProductionExecute(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        auto work=std::make_unique<Work>(); work->kind=Kind::Execute;
        work->convert=ParseConvert(env,Arg(env,info,1)); return Queue(env,std::move(work));
    });
}
napi_value ProductionSubscribe(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        std::size_t count=3; napi_value args[3]{};
        Check(napi_get_cb_info(env,info,&count,args,nullptr,nullptr));
        if (count!=2) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_SUBSCRIBE_ARGUMENTS");
        auto taskId=String(env,args[0]); napi_valuetype type{}; Check(napi_typeof(env,args[1],&type));
        if (type!=napi_function) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_LISTENER_TYPE");
        napi_ref ref{}; Check(napi_create_reference(env,args[1],1,&ref));
        const auto token="sub:"+std::to_string(nextToken.fetch_add(1));
        try { std::lock_guard<std::mutex> lock(listenersMutex); listeners.emplace(token,Listener{taskId,ref}); }
        catch (...) { (void)napi_delete_reference(env,ref); throw; }
        return Text(env,token);
    });
}
napi_value ProductionUnsubscribe(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        auto token=String(env,Arg(env,info,1)); napi_ref ref{};
        {
            std::lock_guard<std::mutex> lock(listenersMutex);
            auto item=listeners.find(token);
            if (item!=listeners.end()) { ref=item->second.ref; listeners.erase(item); }
        }
        if (ref) Check(napi_delete_reference(env,ref));
        napi_value result{}; Check(napi_get_boolean(env,ref!=nullptr,&result)); return result;
    });
}
napi_value ProductionCancel(napi_env env,napi_callback_info info) { return Control(env,info,Kind::Cancel); }
napi_value ProductionPause(napi_env env,napi_callback_info info) { return Control(env,info,Kind::Pause); }
napi_value ProductionResume(napi_env env,napi_callback_info info) { return Control(env,info,Kind::Resume); }
napi_value ProductionReleaseTask(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        const auto taskId=String(env,Arg(env,info,2,0));
        const auto attemptId=String(env,Arg(env,info,2,1));
        {
            std::lock_guard<std::mutex> lock(listenersMutex);
            for (auto it=listeners.begin();it!=listeners.end();) {
                if (it->second.taskId==taskId) {
                    (void)napi_delete_reference(env,it->second.ref);
                    it=listeners.erase(it);
                } else ++it;
            }
        }
        auto work=std::make_unique<Work>(); work->kind=Kind::ReleaseTask;
        work->first=taskId; work->second=attemptId; return Queue(env,std::move(work));
    });
}
napi_value ProductionReleaseArtifact(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        auto work=std::make_unique<Work>(); work->kind=Kind::ReleaseArtifact;
        work->first=String(env,Arg(env,info,1)); return Queue(env,std::move(work));
    });
}
napi_value ProductionCopyArtifact(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        const auto ref=String(env,Arg(env,info,4,0));
        const auto fd=Unsigned(env,Arg(env,info,4,1),static_cast<std::uint64_t>(std::numeric_limits<int>::max()));
        const auto sha256=String(env,Arg(env,info,4,2));
        const auto bytes=Unsigned(env,Arg(env,info,4,3),512ULL*1024*1024);
        auto work=std::make_unique<Work>(); work->kind=Kind::CopyArtifact;
        work->first=ref; work->second=sha256; work->destinationFd=static_cast<int>(fd); work->exportBytes=bytes;
        return Queue(env,std::move(work));
    });
}
napi_value ProductionShutdown(napi_env env,napi_callback_info info) {
    return Boundary(env,[&] {
        std::size_t count=1; napi_value args[1]{};
        Check(napi_get_cb_info(env,info,&count,args,nullptr,nullptr));
        if (count!=0) throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_SHUTDOWN_ARGUMENTS");
        {
            std::lock_guard<std::mutex> lock(listenersMutex);
            for (const auto& [token,entry]:listeners) (void)napi_delete_reference(env,entry.ref);
            listeners.clear();
        }
        auto work=std::make_unique<Work>(); work->kind=Kind::Shutdown;
        return Queue(env,std::move(work));
    });
}
} // namespace hdm
