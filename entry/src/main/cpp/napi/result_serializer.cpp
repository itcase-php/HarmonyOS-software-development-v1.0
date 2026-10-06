#include "result_serializer.h"
#include "bridge_problem.h"

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
napi_value Strings(napi_env env,const std::vector<std::string>& values) {
    auto array=Array(env);
    for (std::uint32_t i=0;i<values.size();++i) Push(env,array,i,Text(env,values[i]));
    return array;
}
const char* Tier(FidelityTier tier) {
    switch (tier) {
        case FidelityTier::Extreme: return "extreme";
        case FidelityTier::Standard: return "standard";
        case FidelityTier::Compatible: return "compatible";
    }
    throw BridgeProblem(ErrorCode::InternalError,"NATIVE_REPORT_TIER");
}
napi_value Report(napi_env env,const FidelityReport& report) {
    auto result=Object(env); PutNumber(env,result,"schemaVersion",report.schemaVersion);
    PutText(env,result,"intent",report.intent==Intent::LayoutPreserved?"layout_preserved":
        report.intent==Intent::StructuredRebuild?"structured_rebuild":"content_only");
    PutText(env,result,"requestedTier",Tier(report.requestedTier));
    if (report.achievedTier) PutText(env,result,"achievedTier",Tier(*report.achievedTier));
    if (report.sourcePageCount) PutNumber(env,result,"sourcePageCount",*report.sourcePageCount);
    if (report.outputPageCount) PutNumber(env,result,"outputPageCount",*report.outputPageCount);
    auto metrics=Array(env);
    for (std::uint32_t i=0;i<report.metrics.size();++i) {
        const auto& metric=report.metrics[i]; auto item=Object(env);
        PutText(env,item,"name",metric.name); PutText(env,item,"unit",metric.unit);
        PutText(env,item,"algorithmVersion",metric.algorithmVersion);
        PutText(env,item,"state",metric.state==MetricState::Measured?"measured":
            metric.state==MetricState::Estimated?"estimated":
            metric.state==MetricState::Unavailable?"unavailable":"not_applicable");
        if (metric.value) PutNumber(env,item,"value",*metric.value);
        if (metric.denominator) PutNumber(env,item,"denominator",*metric.denominator);
        Put(env,item,"evidenceRefs",Strings(env,metric.evidenceRefs)); Push(env,metrics,i,item);
    }
    Put(env,result,"metrics",metrics);
    Put(env,result,"fontSubstitutions",Strings(env,report.fontSubstitutions));
    Put(env,result,"unsupportedFeatures",Strings(env,report.unsupportedFeatures));
    Put(env,result,"degradations",Strings(env,report.degradations));
    Put(env,result,"evidenceRefs",Strings(env,report.evidenceRefs));
    PutBool(env,result,"requiresManualReview",report.requiresManualReview);
    PutText(env,result,"detectorVersion",report.detectorVersion); return result;
}
napi_value Error(napi_env env,const Status& failure) {
    napi_value error{};
    Check(napi_create_error(env,Text(env,ErrorCodeName(failure.code)),Text(env,ErrorCodeName(failure.code)),&error));
    PutText(env,error,"reason",failure.reason); PutText(env,error,"module",failure.module);
    const char* stage="preparing";
    switch (failure.stage) {
        case Stage::Preparing: break;
        case Stage::Executing: stage="executing"; break;
        case Stage::Validating: stage="validating"; break;
        case Stage::Committing: stage="committing"; break;
        case Stage::Cleaning: stage="cleaning"; break;
    }
    PutText(env,error,"stage",stage); PutText(env,error,"traceId",failure.traceId);
    PutText(env,error,"messageKey",failure.messageKey);
    PutBool(env,error,"retryable",failure.retryable);
    if (failure.detailKey) PutText(env,error,"detailKey",*failure.detailKey);
    return error;
}
}
napi_value SerializeConvertResult(napi_env env,const ConvertResult& native) {
    auto result=Object(env); PutNumber(env,result,"schemaVersion",native.schemaVersion);
    PutText(env,result,"taskId",native.taskId); PutText(env,result,"attemptId",native.attemptId);
    PutText(env,result,"status",native.status==ResultState::Success?"success":
        native.status==ResultState::Cancelled?"cancelled":"failed");
    if (native.error) Put(env,result,"error",Error(env,*native.error));
    auto warnings=Array(env);
    for (std::uint32_t i=0;i<native.warnings.size();++i) {
        const auto& warning=native.warnings[i]; auto item=Object(env);
        PutText(env,item,"code",ErrorCodeName(warning.code)); PutText(env,item,"reason",warning.reason);
        PutText(env,item,"messageKey",warning.messageKey);
        PutBool(env,item,"requiresManualReview",warning.requiresManualReview);
        if (warning.evidenceRef) PutText(env,item,"evidenceRef",*warning.evidenceRef);
        Push(env,warnings,i,item);
    }
    Put(env,result,"warnings",warnings);
    if (native.fidelity) Put(env,result,"fidelity",Report(env,*native.fidelity));
    auto outputs=Array(env);
    for (std::uint32_t i=0;i<native.outputs.size();++i) {
        const auto& output=native.outputs[i]; auto item=Object(env);
        PutText(env,item,"artifactId",output.artifactId); PutText(env,item,"role",output.role);
        PutText(env,item,"formatId",output.formatId); PutText(env,item,"internalRef",output.internalRef);
        PutText(env,item,"sha256",output.sha256); PutNumber(env,item,"byteSize",output.byteSize);
        if (output.pageIndex) PutNumber(env,item,"pageIndex",*output.pageIndex);
        Push(env,outputs,i,item);
    }
    Put(env,result,"outputs",outputs);
    auto validation=Object(env);
    PutText(env,validation,"state",native.validation.state==ValidationState::Passed?"passed":
        native.validation.state==ValidationState::Failed?"failed":"not_evaluated");
    PutText(env,validation,"validatorVersion",native.validation.validatorVersion.empty()?"not-evaluated":native.validation.validatorVersion);
    auto evidence=Array(env);
    for (std::uint32_t i=0;i<native.validation.evidenceRefs.size();++i)
        Push(env,evidence,i,Text(env,native.validation.evidenceRefs[i]));
    Put(env,validation,"evidenceRefs",evidence); Put(env,result,"validation",validation);
    auto engines=Array(env);
    for (std::uint32_t i=0;i<native.engines.size();++i) {
        auto item=Object(env); PutText(env,item,"engineId",native.engines[i].engineId);
        PutText(env,item,"version",native.engines[i].version);
        PutText(env,item,"buildHash",native.engines[i].buildHash); Push(env,engines,i,item);
    }
    Put(env,result,"engines",engines);
    PutNumber(env,result,"elapsedMs",native.elapsedMs);
    PutNumber(env,result,"nativePeakBytes",native.nativePeakBytes);
    PutNumber(env,result,"tempPeakBytes",native.tempPeakBytes);
    return result;
}
}
