#include "runtime.h"
#include "sha256.h"
#include "image_context.h"
#include "output_validator.h"
#include "../napi/bridge_problem.h"
#include "../core/engine_registry.h"
#include "../generated/registry_metadata.h"
#include "../../../../../prototypes/jpeg-pdf/src/jpeg_probe.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <fstream>
#include <random>
#include <system_error>
#ifdef __OHOS__
#include <cstdio>
#include <fcntl.h>
#endif
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

namespace hdm::production {
namespace {
namespace fs = std::filesystem;
constexpr std::uint64_t kMaximumInput = 100ULL*1024*1024;
constexpr std::uint64_t kMaximumTemp = 512ULL*1024*1024;
constexpr std::uint64_t kMaximumPixels = 16000000;
bool IsId(const std::string& id) {
    return id.size()>=32 && id.size()<=36 &&
        std::all_of(id.begin(),id.end(),[](unsigned char c) {
            return (c>='0'&&c<='9') || (c>='a'&&c<='f') || c=='-';
        });
}
std::string RandomId() {
    std::random_device random;
    constexpr char hex[]="0123456789abcdef";
    std::string id; id.reserve(32);
    for (int i=0;i<16;++i) { const unsigned char byte=static_cast<unsigned char>(random());
        id.push_back(hex[byte>>4]); id.push_back(hex[byte&15]); }
    return id;
}
bool SafeDirectory(const fs::path& path) {
    std::error_code ec;
    return !fs::is_symlink(fs::symlink_status(path,ec)) && !ec && fs::is_directory(path,ec) && !ec;
}
bool SafeFile(const fs::path& path) {
    std::error_code ec;
    return !fs::is_symlink(fs::symlink_status(path,ec)) && !ec && fs::is_regular_file(path,ec) && !ec;
}
std::string TaskKey(const std::string& taskId, const std::string& attemptId) { return taskId+":"+attemptId; }
Status Failure(ErrorCode code, const char* reason) {
    Status status; status.code=code; status.reason=reason; status.module="NativeBridge";
    status.messageKey=std::string("errors.")+ErrorCodeName(code); return status;
}
std::string DigestFile(const fs::path& path, std::uint64_t maximum, std::uint64_t& bytes) {
    std::ifstream input(path,std::ios::binary);
    if (!input) throw BridgeProblem(ErrorCode::InputNotFound,"NATIVE_INPUT_OPEN");
    Sha256 hash; std::array<char,64*1024> buffer{}; bytes=0;
    while (input) {
        input.read(buffer.data(),buffer.size()); const auto got=input.gcount();
        if (got<0 || bytes>maximum || static_cast<std::uint64_t>(got)>maximum-bytes)
            throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_INPUT_LIMIT");
        hash.Update(buffer.data(),static_cast<std::size_t>(got)); bytes+=static_cast<std::uint64_t>(got);
    }
    if (!input.eof()) throw BridgeProblem(ErrorCode::IoError,"NATIVE_INPUT_READ");
    return hash.FinalHex();
}
struct ProbeIO {
    prototype::IStream& input;
    std::uint64_t bytes{}, maximum{};
    Sha256 hash;
};
extern "C" int ReadJpeg(void* opaque, unsigned char* buffer, size_t capacity, size_t* count) noexcept {
    auto& io=*static_cast<ProbeIO*>(opaque);
    try {
        *count=io.input.Read(buffer,capacity);
        if (*count>capacity || io.bytes>io.maximum || *count>io.maximum-io.bytes)
            return static_cast<int>(ErrorCode::ResourceLimitExceeded);
        io.hash.Update(buffer,*count); io.bytes+=*count; return 0;
    } catch (const BridgeProblem& failure) { return static_cast<int>(failure.code); }
    catch (...) { return static_cast<int>(ErrorCode::IoError); }
}
extern "C" int CheckJpeg(void*) noexcept { return 0; }
InputProbe ProbeOne(const fs::path& directory, const PreparedInput& input, const ResourceBudget& budget) {
    InputProbe result; result.fileId=input.fileId;
    if (!IsId(input.fileId) || input.relativePath!="inputs/"+input.fileId ||
        input.sourceFormatId!="jpeg" || input.byteSize==0 || input.byteSize>budget.maxInputBytes ||
        input.byteSize>kMaximumInput || input.sha256.size()!=64) return result;
    const fs::path inputs=directory/"inputs";
    const fs::path path=inputs/input.fileId;
    if (!SafeDirectory(inputs) || !SafeFile(path)) return result;
    try {
        prototype::HostFile source(path.string(),false);
        if (source.Size()!=input.byteSize) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_INPUT_SIZE_MISMATCH");
        ProbeIO io{source,0,std::min<std::uint64_t>(budget.maxInputBytes,kMaximumInput),Sha256{}};
        HdmJpegInfo info{};
        const int code=hdm_probe_jpeg(ReadJpeg,CheckJpeg,&io,
            budget.maxNativeBytes,std::min<std::uint64_t>(budget.maxPixels,kMaximumPixels),&info);
        if (code==static_cast<int>(ErrorCode::FileCorrupted))
            throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_JPEG_CORRUPTED");
        if (code==static_cast<int>(ErrorCode::ResourceLimitExceeded))
            throw BridgeProblem(ErrorCode::ResourceLimitExceeded,info.issue==HDM_JPEG_PIXELS ? "NATIVE_JPEG_PIXEL_LIMIT" : "NATIVE_JPEG_MEMORY_LIMIT");
        if (code==static_cast<int>(ErrorCode::UnsupportedFeature)) {
            const char* reason="NATIVE_JPEG_SUBSET_UNSUPPORTED";
            switch (info.issue) {
                case HDM_JPEG_METADATA: reason="NATIVE_JPEG_METADATA_UNSUPPORTED"; break;
                case HDM_JPEG_ENCODING: reason="NATIVE_JPEG_ENCODING_UNSUPPORTED"; break;
                case HDM_JPEG_COLOR: reason="NATIVE_JPEG_COLOR_UNSUPPORTED"; break;
                case HDM_JPEG_DENSITY: reason="NATIVE_JPEG_DENSITY_UNSUPPORTED"; break;
                case HDM_JPEG_HEADER: reason="NATIVE_JPEG_HEADER_UNSUPPORTED"; break;
            }
            throw BridgeProblem(ErrorCode::UnsupportedFeature,reason);
        }
        if (code!=0) throw BridgeProblem(ErrorCode::IoError,"NATIVE_INPUT_READ_FAILED");
        if (io.bytes!=input.byteSize) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_INPUT_SIZE_MISMATCH");
        if (io.hash.FinalHex()!=input.sha256) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_INPUT_DIGEST_MISMATCH");
        result.actualFormatId="jpeg";
        result.protection=ProtectionState::None;
        result.pageCount=1;
        result.needsDeepCheck=false;
    } catch (const BridgeProblem&) { throw; }
    catch (...) { return result; }
    return result;
}
} // namespace

Runtime& SharedRuntime() { static Runtime runtime; return runtime; }

std::string Runtime::Initialize(const SessionInit& init) {
    if (init.schemaVersion!=kSchemaVersion || init.configVersion!=kConfigVersion ||
        init.configSha256!=kMatrixHash) throw BridgeProblem(ErrorCode::ConfigInvalid,"NATIVE_CONFIG_MISMATCH");
    const fs::path supplied(init.appSandboxRoot);
    if (!supplied.is_absolute() || supplied.filename()!="cache" || !SafeDirectory(supplied))
        throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_SANDBOX_ROOT");
    std::error_code ec; const auto root=fs::canonical(supplied,ec);
    if (ec || !SafeDirectory(root)) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_SANDBOX_ROOT");
    std::lock_guard<std::mutex> lock(mutex_);
    std::string id; do { id=RandomId(); } while (sessions_.count(id));
    sessions_.emplace(id,Session{root,{}});
    return id;
}

std::string Runtime::Register(const WorkspaceGrant& grant) {
    if (!IsId(grant.taskId) || !IsId(grant.attemptId) || grant.relativeDirectory.size()<42 ||
        grant.relativeDirectory.substr(0,10)!="workspace/" ||
        !IsId(grant.relativeDirectory.substr(10)))
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_WORKSPACE_GRANT");
    std::lock_guard<std::mutex> lock(mutex_);
    auto session=sessions_.find(grant.sessionId);
    if (session==sessions_.end()) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_SESSION_UNKNOWN");
    const auto workspace=session->second.root/"workspace";
    const auto directory=workspace/grant.relativeDirectory.substr(10);
    if (!SafeDirectory(workspace) || !SafeDirectory(directory) || !SafeDirectory(directory/"inputs"))
        throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_WORKSPACE_INVALID");
    const std::string ref=grant.sessionId+":"+TaskKey(grant.taskId,grant.attemptId);
    if (session->second.grants.count(ref)) throw BridgeProblem(ErrorCode::TaskBusy,"NATIVE_GRANT_EXISTS");
    session->second.grants.emplace(ref,Grant{grant.sessionId,grant.taskId,grant.attemptId,ref,directory,
        std::make_shared<std::atomic<bool>>(false)});
    return ref;
}

Grant Runtime::GetGrant(const std::string& sessionId, const std::string& workspaceRef) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto session=sessions_.find(sessionId);
    if (session==sessions_.end()) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_SESSION_UNKNOWN");
    const auto grant=session->second.grants.find(workspaceRef);
    if (grant==session->second.grants.end()) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_WORKSPACE_UNKNOWN");
    return grant->second;
}

bool Runtime::HasSession(const std::string& sessionId) const {
    std::lock_guard<std::mutex> lock(mutex_); return sessions_.count(sessionId)!=0;
}

ProbeResult Runtime::Probe(const ProbeRequest& request) {
    if (request.schemaVersion!=kSchemaVersion || request.inputs.empty() || request.inputs.size()>100)
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_PROBE_REQUEST");
    const auto grant=GetGrant(request.sessionId,request.workspaceRef);
    ProbeResult result;
    for (const auto& input:request.inputs) result.inputs.push_back(ProbeOne(grant.directory,input,request.resourceBudget));
    return result;
}

ConvertResult Runtime::Execute(const ConvertRequest& request) {
    ConvertResult result; result.schemaVersion=kSchemaVersion; result.taskId=request.taskId; result.attemptId=request.attemptId;
    const auto started=std::chrono::steady_clock::now();
    try {
        if (request.schemaVersion!=kSchemaVersion || request.plan.configVersion!=kConfigVersion ||
            request.plan.configSha256!=kMatrixHash || request.plan.routeId!=kJpegPdfRouteId ||
            request.inputs.size()!=1 || request.plan.steps.size()!=1 ||
            request.plan.policyVersion!=kSecurityPolicyVersion ||
            request.plan.intent!=Intent::LayoutPreserved || request.intent!=Intent::LayoutPreserved ||
            request.operation!=Operation::ImagesToPdf ||
            !request.plan.fallbackRouteIds.empty() || !request.plan.allowedDegradations.empty() ||
            request.options.pdf || request.options.image || request.options.office ||
            request.options.audio || request.options.ocr ||
            request.plan.steps[0].stepId!="jpeg-pdf-1" ||
            request.plan.steps[0].executorEngineId!="image" ||
            request.plan.steps[0].outputFormatId!="pdf" ||
            request.plan.steps[0].operation!=Operation::ImagesToPdf ||
            request.plan.steps[0].engineIds!=std::vector<std::string>({"image","pdf"}) ||
            request.plan.steps[0].inputFormatIds!=std::vector<std::string>({"jpeg"}) ||
            request.targetFormatId!="pdf")
            throw BridgeProblem(ErrorCode::ConfigInvalid,"NATIVE_PLAN_MISMATCH");
        const auto grant=GetGrant(request.sessionId,request.workspaceRef);
        if (grant.taskId!=request.taskId || grant.attemptId!=request.attemptId)
            throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_TASK_OWNERSHIP");
        const auto probe=ProbeOne(grant.directory,request.inputs[0],request.resourceBudget);
        if (!probe.actualFormatId || *probe.actualFormatId!="jpeg" || probe.protection!=ProtectionState::None || probe.needsDeepCheck)
            throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_INPUT_NOT_VERIFIED");
        const fs::path outputs=grant.directory/"outputs";
        std::error_code ec; fs::create_directory(outputs,ec);
        if (ec || !SafeDirectory(outputs)) throw BridgeProblem(ErrorCode::IoError,"NATIVE_OUTPUT_DIRECTORY");
        // Input sessions are deleted after execution. Committed artifacts remain owned by
        // the result until ReleaseArtifact/Shutdown, outside that temporary workspace.
        const fs::path artifacts=grant.directory.parent_path().parent_path()/"artifacts";
        fs::create_directory(artifacts,ec);
        if (ec || !SafeDirectory(artifacts)) throw BridgeProblem(ErrorCode::IoError,"NATIVE_ARTIFACT_DIRECTORY");
        const auto nonce=RandomId();
        const auto spoolPath=outputs/(nonce+".spool");
        const auto candidatePath=outputs/(nonce+".candidate");
        const auto finalPath=artifacts/(nonce+".pdf");
        struct Cleanup {
            fs::path spool,candidate,final;
            bool committed{};
            ~Cleanup() { std::error_code ec; fs::remove(spool,ec); fs::remove(candidate,ec);
                if (!committed) fs::remove(final,ec); }
        } cleanup{spoolPath,candidatePath,finalPath};
        prototype::HostFile source((grant.directory/request.inputs[0].relativePath).string(),false);
        prototype::HostFile spool(spoolPath.string(),true);
        prototype::HostFile candidate(candidatePath.string(),true);
        ImageContext context(source,spool,candidate,*grant.cancelled,
            started+std::chrono::milliseconds(request.resourceBudget.timeoutMs),"outputs/"+nonce+".candidate");
        ConverterLease engine(CreateConverter("image"));
        if (!engine.Get()) throw BridgeProblem(ErrorCode::EngineMissing,"NATIVE_IMAGE_MISSING");
        EngineInitContext init; init.hardLimits=request.resourceBudget;
        auto status=engine.Get()->Initialize(init);
        if (!status.IsOk()) throw BridgeProblem(status.code,status.reason);
        status=engine.Get()->Validate(request,context);
        if (!status.IsOk()) throw BridgeProblem(status.code,status.reason);
        status=engine.Get()->Execute(request,context);
        if (!status.IsOk()) throw BridgeProblem(status.code,status.reason);
        auto candidateOutput=engine.Get()->CollectOutput(context);
        if (!candidateOutput.status.IsOk() || !candidateOutput.value || candidateOutput.value->files.size()!=1)
            throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_OUTPUT_INVALID");
        candidate.Flush();
        if (!context.result || !ValidateKnownPdf(candidate,context.result->candidate))
            throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_PDF_STRUCTURE");
        std::uint64_t pdfBytes{}; const auto pdfHash=DigestFile(candidatePath,kMaximumTemp,pdfBytes);
        if (pdfBytes!=candidateOutput.value->files[0].byteSize)
            throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_OUTPUT_SIZE");
#ifdef __OHOS__
        // The app sandbox rejects hard links; commit atomically without replacing a file.
        if (::renameat2(AT_FDCWD,candidatePath.c_str(),AT_FDCWD,finalPath.c_str(),RENAME_NOREPLACE)!=0)
            throw BridgeProblem(ErrorCode::IoError,"NATIVE_OUTPUT_COMMIT");
#else
        fs::create_hard_link(candidatePath,finalPath,ec);
        if (ec) throw BridgeProblem(ErrorCode::IoError,"NATIVE_OUTPUT_COMMIT");
#endif
        const std::string artifactId=nonce;
        const std::string internalRef="artifact:"+nonce;
        result.outputs.push_back({artifactId,"primary","pdf",internalRef,pdfHash,pdfBytes,std::nullopt});
        result.validation={ValidationState::Passed,"jpeg-pdf-structure-payload-v1",
            {"pdf-fixed-structure","jpeg-payload-identical"}};
        result.engines.push_back(engine.Get()->Describe().engine);
        result.nativePeakBytes=context.result->candidate.trackedAllocationPeak;
        result.tempPeakBytes=context.result->candidate.tempPeak;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!artifacts_.emplace(internalRef,ArtifactState{finalPath,request.taskId,request.attemptId,pdfHash,pdfBytes}).second)
                throw BridgeProblem(ErrorCode::TaskBusy,"NATIVE_ARTIFACT_EXISTS");
        }
        cleanup.committed=true;
        result.status=ResultState::Success;
    } catch (const BridgeProblem& failure) {
        result.status=failure.code==ErrorCode::ConversionCancelled?ResultState::Cancelled:ResultState::Failed;
        result.error=Failure(failure.code,failure.what());
    } catch (const std::bad_alloc&) {
        result.error=Failure(ErrorCode::ResourceLimitExceeded,"NATIVE_ALLOCATION_FAILED");
    } catch (...) {
        result.error=Failure(ErrorCode::InternalError,"NATIVE_EXECUTION_FAILED");
    }
    result.elapsedMs=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started).count();
    return result;
}

ControlAck Runtime::Control(const std::string& taskId, const std::string& attemptId, const char* action) {
    ControlAck ack; ack.taskId=taskId; ack.attemptId=attemptId;
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& [id,session]:sessions_) for (auto& [ref,grant]:session.grants) {
        if (grant.taskId!=taskId || grant.attemptId!=attemptId) continue;
        if (std::string(action)!="cancel") { ack.state=ControlAck::State::Unsupported; return ack; }
        grant.cancelled->store(true); ack.state=ControlAck::State::Accepted; return ack;
    }
    return ack;
}
void Runtime::ReleaseTask(const std::string& taskId, const std::string& attemptId) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto session=sessions_.begin();session!=sessions_.end();) {
        for (auto grant=session->second.grants.begin();grant!=session->second.grants.end();) {
            if (grant->second.taskId==taskId && grant->second.attemptId==attemptId) {
                grant->second.cancelled->store(true); grant=session->second.grants.erase(grant);
            } else ++grant;
        }
        if (session->second.grants.empty()) session=sessions_.erase(session); else ++session;
    }
}
void Runtime::ReleaseArtifact(const std::string& ref) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto artifact=artifacts_.find(ref); if (artifact==artifacts_.end()) return;
    std::error_code ec; fs::remove(artifact->second.path,ec);
    if (ec) throw BridgeProblem(ErrorCode::IoError,"NATIVE_ARTIFACT_RELEASE");
    artifacts_.erase(artifact);
}
std::uint64_t Runtime::CopyArtifactToFd(const std::string& ref, int fd,
                                       const std::string& sha256, std::uint64_t byteSize) {
    if (fd<0 || ref.rfind("artifact:",0)!=0 || sha256.size()!=64 || byteSize==0 || byteSize>kMaximumTemp)
        throw BridgeProblem(ErrorCode::InvalidRequest,"NATIVE_EXPORT_ARGUMENTS");
    // Keep the artifact owned until the copy ends, so release/shutdown cannot remove it mid-transfer.
    std::lock_guard<std::mutex> lock(mutex_);
    const auto found=artifacts_.find(ref);
    if (found==artifacts_.end()) throw BridgeProblem(ErrorCode::InputNotFound,"NATIVE_ARTIFACT_MISSING");
    const auto& artifact=found->second;
    if (artifact.sha256!=sha256 || artifact.byteSize!=byteSize || !SafeFile(artifact.path))
        throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_ARTIFACT_METADATA");
    std::uint64_t verifiedBytes{};
    if (DigestFile(artifact.path,kMaximumTemp,verifiedBytes)!=sha256 || verifiedBytes!=byteSize)
        throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_ARTIFACT_CHANGED");
    std::ifstream input(artifact.path,std::ios::binary);
    if (!input) throw BridgeProblem(ErrorCode::IoError,"NATIVE_EXPORT_READ");
    std::array<char,64*1024> buffer{};
    std::uint64_t copied{};
    Sha256 copiedHash;
    while (input) {
        input.read(buffer.data(),buffer.size());
        const auto got=input.gcount();
        if (got<0 || static_cast<std::uint64_t>(got)>byteSize-copied)
            throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_ARTIFACT_CHANGED");
        copiedHash.Update(buffer.data(),static_cast<std::size_t>(got));
        std::streamsize offset{};
        while (offset<got) {
#ifdef _WIN32
            const int written=_write(fd,buffer.data()+offset,static_cast<unsigned int>(got-offset));
#else
            const auto written=write(fd,buffer.data()+offset,static_cast<std::size_t>(got-offset));
#endif
            if (written<=0) throw BridgeProblem(ErrorCode::IoError,"NATIVE_EXPORT_WRITE");
            offset+=written;
        }
        copied+=static_cast<std::uint64_t>(got);
    }
    if (!input.eof() || copied!=byteSize || copiedHash.FinalHex()!=sha256)
        throw BridgeProblem(ErrorCode::OutputValidationFailed,"NATIVE_EXPORT_INCOMPLETE");
    return copied;
}
void Runtime::Shutdown() {
    std::vector<fs::path> paths;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto& [id,session]:sessions_) for (auto& [ref,grant]:session.grants) grant.cancelled->store(true);
        sessions_.clear();
        for (const auto& [ref,artifact]:artifacts_) paths.push_back(artifact.path);
        artifacts_.clear();
    }
    std::error_code ec; for (const auto& path:paths) fs::remove(path,ec);
}
} // namespace hdm::production
