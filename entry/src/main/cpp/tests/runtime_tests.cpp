#include "../production/runtime.h"
#include "../production/sha256.h"
#include "../napi/bridge_problem.h"
#include "../generated/registry_metadata.h"
#include <array>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <fcntl.h>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

namespace {
namespace fs=std::filesystem;
void Require(bool value,const char* message) { if (!value) throw std::runtime_error(message); }
std::string Digest(const fs::path& path) {
    std::ifstream input(path,std::ios::binary); std::array<char,1024> buffer{};
    hdm::production::Sha256 sha;
    while (input) { input.read(buffer.data(),buffer.size()); sha.Update(buffer.data(),static_cast<std::size_t>(input.gcount())); }
    return sha.FinalHex();
}
hdm::ResourceBudget Budget() {
    hdm::ResourceBudget result;
    result.maxInputBytes=104857600; result.maxBatchBytes=314572800;
    result.maxNativeBytes=201326592; result.maxTempBytes=536870912;
    result.maxPages=300; result.maxPixels=16000000; result.maxThreads=2; result.timeoutMs=180000;
    return result;
}
struct Fixture {
    fs::path root,cache,workspace,input;
    hdm::production::Runtime runtime;
    std::string session,ref;
    const std::string workspaceId="11111111111111111111111111111111";
    const std::string fileId="22222222222222222222222222222222";
    const std::string taskId="33333333333333333333333333333333";
    const std::string attemptId="44444444444444444444444444444444";
    Fixture(const fs::path& source) {
        root=fs::temp_directory_path()/("hdm-runtime-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        cache=root/"cache"; workspace=cache/"workspace"/workspaceId;
        fs::create_directories(workspace/"inputs"); input=workspace/"inputs"/fileId;
        fs::copy_file(source,input);
        session=runtime.Initialize({hdm::kSchemaVersion,cache.string(),hdm::kConfigVersion,hdm::kMatrixHash});
        ref=runtime.Register({session,taskId,attemptId,"workspace/"+workspaceId});
    }
    ~Fixture() { runtime.Shutdown(); std::error_code ec; fs::remove_all(root,ec); }
    hdm::PreparedInput Prepared() const {
        return {fileId,"jpeg","inputs/"+fileId,Digest(input),fs::file_size(input)};
    }
    hdm::ProbeRequest ProbeRequest() const { return {hdm::kSchemaVersion,session,ref,{Prepared()},Budget()}; }
    hdm::ConvertRequest Request() const {
        hdm::ConvertRequest request;
        request.schemaVersion=hdm::kSchemaVersion; request.sessionId=session; request.taskId=taskId;
        request.attemptId=attemptId; request.workspaceRef=ref; request.operation=hdm::Operation::ImagesToPdf;
        request.inputs={Prepared()}; request.targetFormatId="pdf"; request.qualityMode=hdm::QualityMode::Balanced;
        request.intent=hdm::Intent::LayoutPreserved; request.resourceBudget=Budget();
        request.plan.routeId=hdm::kJpegPdfRouteId; request.plan.configVersion=hdm::kConfigVersion;
        request.plan.configSha256=hdm::kMatrixHash; request.plan.policyVersion="v1-protected-block";
        request.plan.intent=hdm::Intent::LayoutPreserved; request.plan.minimumTier=hdm::FidelityTier::Extreme;
        hdm::PlanStep step; step.stepId="jpeg-pdf-1"; step.executorEngineId="image";
        step.engineIds={"image","pdf"}; step.inputFormatIds={"jpeg"};
        step.outputFormatId="pdf"; step.operation=hdm::Operation::ImagesToPdf;
        request.plan.steps.push_back(step); return request;
    }
};
}
int main(int argc,char** argv) {
    try {
        Require(argc==2 || argc==3,"fixture path required");
        Fixture fixture(argv[1]);
        const auto probe=fixture.runtime.Probe(fixture.ProbeRequest());
        Require(probe.inputs.size()==1 && probe.inputs[0].actualFormatId=="jpeg" &&
            probe.inputs[0].protection==hdm::ProtectionState::None && !probe.inputs[0].needsDeepCheck,
            "valid JPEG probe failed");
        const auto result=fixture.runtime.Execute(fixture.Request());
        Require(result.status==hdm::ResultState::Success && result.outputs.size()==1 &&
            result.validation.state==hdm::ValidationState::Passed,"valid JPEG conversion failed");
        const auto output=fixture.workspace/"outputs"/(result.outputs[0].artifactId+".pdf");
        Require(fs::exists(output) && fs::file_size(output)==result.outputs[0].byteSize &&
            Digest(output)==result.outputs[0].sha256,"committed PDF mismatch");
        const auto exported=fixture.root/"export.pdf";
#ifdef _WIN32
        const int fd=_open(exported.string().c_str(),_O_CREAT|_O_TRUNC|_O_WRONLY|_O_BINARY,_S_IREAD|_S_IWRITE);
#else
        const int fd=open(exported.string().c_str(),O_CREAT|O_TRUNC|O_WRONLY,0600);
#endif
        Require(fd>=0,"export descriptor open failed");
        const auto copied=fixture.runtime.CopyArtifactToFd(result.outputs[0].internalRef,fd,
            result.outputs[0].sha256,result.outputs[0].byteSize);
#ifdef _WIN32
        _close(fd);
#else
        close(fd);
#endif
        Require(copied==result.outputs[0].byteSize && Digest(exported)==result.outputs[0].sha256,
            "verified export copy failed");
        bool rejected=false;
        try { fixture.runtime.CopyArtifactToFd(result.outputs[0].internalRef,-1,
            result.outputs[0].sha256,result.outputs[0].byteSize); }
        catch (const hdm::BridgeProblem&) { rejected=true; }
        Require(rejected,"invalid export descriptor accepted");
        if (argc==3) fs::copy_file(output,argv[2],fs::copy_options::overwrite_existing);
        auto forged=fixture.Request(); forged.plan.steps[0].inputFormatIds={"png"};
        Require(fixture.runtime.Execute(forged).status==hdm::ResultState::Failed,
            "forged plan converted");
        forged=fixture.Request(); forged.plan.policyVersion="old-policy";
        Require(fixture.runtime.Execute(forged).status==hdm::ResultState::Failed,
            "stale protection policy converted");
        forged=fixture.Request(); forged.inputs[0].sha256=std::string(64,'0');
        Require(fixture.runtime.Execute(forged).status==hdm::ResultState::Failed,
            "mismatched input digest converted");
        fixture.runtime.ReleaseTask(fixture.taskId,fixture.attemptId);
        Require(fs::exists(output),"releaseTask removed owned artifact");
        fixture.runtime.ReleaseArtifact(result.outputs[0].internalRef);
        Require(!fs::exists(output),"releaseArtifact failed");
        fixture.runtime.ReleaseArtifact(result.outputs[0].internalRef);
        Fixture corrupt(argv[1]);
        { std::ofstream stream(corrupt.input,std::ios::binary|std::ios::trunc); stream<<"not a JPEG"; }
        bool invalidJpeg=false;
        try { corrupt.runtime.Probe(corrupt.ProbeRequest()); }
        catch (const hdm::BridgeProblem& error) {
            invalidJpeg=error.code==hdm::ErrorCode::FileCorrupted &&
                std::string(error.what())=="NATIVE_JPEG_CORRUPTED";
        }
        Require(invalidJpeg,"spoofed JPEG did not report corruption");
        Require(corrupt.runtime.Execute(corrupt.Request()).status==hdm::ResultState::Failed,
            "spoofed JPEG converted");
        Fixture metadata(argv[1]);
        { std::ifstream source(argv[1],std::ios::binary);
          std::string bytes((std::istreambuf_iterator<char>(source)),std::istreambuf_iterator<char>());
          bytes.insert(2,std::string("\xff\xe3\x00\x08" "opaque",10));
          std::ofstream output(metadata.input,std::ios::binary|std::ios::trunc); output.write(bytes.data(),bytes.size()); }
        bool unsupportedMetadata=false;
        try { metadata.runtime.Probe(metadata.ProbeRequest()); }
        catch (const hdm::BridgeProblem& error) {
            unsupportedMetadata=error.code==hdm::ErrorCode::UnsupportedFeature &&
                std::string(error.what())=="NATIVE_JPEG_METADATA_UNSUPPORTED";
        }
        Require(unsupportedMetadata,"JPEG metadata was confused with protection failure");
        Fixture limited(argv[1]);
        auto limitedRequest=limited.ProbeRequest(); limitedRequest.resourceBudget.maxPixels=1;
        bool pixelsExceeded=false;
        try { limited.runtime.Probe(limitedRequest); }
        catch (const hdm::BridgeProblem& error) {
            pixelsExceeded=error.code==hdm::ErrorCode::ResourceLimitExceeded &&
                std::string(error.what())=="NATIVE_JPEG_PIXEL_LIMIT";
        }
        Require(pixelsExceeded,"JPEG pixel limit was confused with protection failure");
        Fixture changed(argv[1]);
        auto changedRequest=changed.ProbeRequest(); changedRequest.inputs[0].sha256=std::string(64,'0');
        bool digestMismatch=false;
        try { changed.runtime.Probe(changedRequest); }
        catch (const hdm::BridgeProblem& error) {
            digestMismatch=error.code==hdm::ErrorCode::PermissionDenied &&
                std::string(error.what())=="NATIVE_INPUT_DIGEST_MISMATCH";
        }
        Require(digestMismatch,"input digest mismatch was confused with protection failure");
        Fixture cancelled(argv[1]);
        Require(cancelled.runtime.Control(cancelled.taskId,cancelled.attemptId,"cancel").state==
            hdm::ControlAck::State::Accepted,"cancel not acknowledged");
        Require(cancelled.runtime.Execute(cancelled.Request()).status==hdm::ResultState::Cancelled,
            "cancelled conversion succeeded");
        std::cout<<"PASS production runtime\n"; return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
