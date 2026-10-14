#include "../production/runtime.h"
#include "../production/office_input.h"
#include "../production/sha256.h"
#include "../generated/registry_metadata.h"
#include "../napi/bridge_problem.h"
#include <array>
#include <fstream>
#include <iostream>
#include <chrono>
#include <cstdio>
#if defined(_WIN32)
#include <io.h>
#else
#include <unistd.h>
#endif
namespace fs=std::filesystem;
std::string Digest(const fs::path& path) {
    hdm::production::Sha256 digest; std::ifstream file(path,std::ios::binary); std::array<char,65536> buffer{};
    if (!file) throw hdm::BridgeProblem(hdm::ErrorCode::IoError,"CLI_INPUT_OPEN");
    while (file) { file.read(buffer.data(),buffer.size()); digest.Update(buffer.data(),static_cast<std::size_t>(file.gcount())); }
    if (!file.eof()) throw hdm::BridgeProblem(hdm::ErrorCode::IoError,"CLI_INPUT_READ");
    return digest.FinalHex();
}
int main(int argc,char** argv) {
    const auto usage=[]() {
        std::cerr<<"Usage: hdm_document_cli jpeg|png INPUT OUTPUT.pdf\n"
            <<"       hdm_document_cli docx|pptx INPUT (package inspection only; no PDF conversion)\n";
        return 99;
    };
    if (argc<3) return usage();
    hdm::ResourceBudget budget{104857600,314572800,201326592,536870912,300,16000000,2,180000};
    try {
        const std::string format=argv[1];
        if (format=="docx" || format=="pptx") {
            if (argc!=3) return usage();
            const auto input=hdm::production::InspectOffice(argv[2],format,budget);
            std::uint64_t characters{};for(const auto& item:input.content.textMinimum)characters+=item.second;
            std::cout<<"inspection only: slides="<<input.slides<<" fonts="<<input.fonts.size()<<" characters="<<characters
                <<" images="<<input.content.minimumImages<<" private="<<input.hasPrivateGlyphs<<'\n';return 0;
        }
        if (argc!=4 || (format!="jpeg" && format!="png")) return usage();
        const auto root=fs::temp_directory_path()/("hdm-document-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        struct Cleanup { fs::path root; ~Cleanup(){std::error_code ec;fs::remove_all(root,ec);} } cleanup{root};
        const std::string id(32,'a'),task(32,'b'),attempt(32,'c');
        const auto cache=root/"cache",work=cache/"workspace"/id,input=work/"inputs"/id;
        fs::create_directories(work/"inputs"); fs::copy_file(argv[2],input);
        hdm::production::Runtime runtime;
        const auto session=runtime.Initialize({1,cache.string(),hdm::kConfigVersion,hdm::kMatrixHash});
        const auto workspace=runtime.Register({session,task,attempt,"workspace/"+id});
        hdm::PreparedInput prepared{id,format,"inputs/"+id,Digest(input),fs::file_size(input)};
        const auto probe=runtime.Probe({1,session,workspace,{prepared},budget});
        if (probe.inputs.size()!=1 || probe.inputs[0].actualFormatId!=format || probe.inputs[0].needsDeepCheck)
            throw hdm::BridgeProblem(hdm::ErrorCode::OutputValidationFailed,"CLI_PROBE");
        hdm::ConvertRequest request; request.schemaVersion=1; request.sessionId=session; request.taskId=task; request.attemptId=attempt;
        request.workspaceRef=workspace; request.inputs={prepared}; request.targetFormatId="pdf";
        request.intent=hdm::Intent::LayoutPreserved; request.operation=hdm::Operation::ImagesToPdf; request.resourceBudget=budget;
        request.plan.routeId=format+"-pdf"; request.plan.configVersion=hdm::kConfigVersion; request.plan.configSha256=hdm::kMatrixHash;
        request.plan.policyVersion=hdm::kSecurityPolicyVersion; request.plan.intent=request.intent;
        request.plan.steps={{format+"-pdf-1","image","pdf",{"image","pdf"},{format},request.operation}};
        const auto result=runtime.Execute(request);
        if (result.status!=hdm::ResultState::Success) {
            if (result.error) throw hdm::BridgeProblem(result.error->code,result.error->reason);
            return 98;
        }
        const auto& artifact=result.outputs.at(0);
        runtime.ReleaseTask(task,attempt); fs::remove_all(work);
        std::unique_ptr<std::FILE,decltype(&std::fclose)> output(std::fopen(argv[3],"wb"),&std::fclose);
        if (!output) throw hdm::BridgeProblem(hdm::ErrorCode::IoError,"CLI_OUTPUT_OPEN");
#if defined(_WIN32)
        const int fd=_fileno(output.get());
#else
        const int fd=fileno(output.get());
#endif
        if (runtime.CopyArtifactToFd(artifact.internalRef,fd,artifact.sha256,artifact.byteSize)!=artifact.byteSize)
            throw hdm::BridgeProblem(hdm::ErrorCode::IoError,"CLI_OUTPUT_SIZE");
        if (std::fclose(output.release())!=0) throw hdm::BridgeProblem(hdm::ErrorCode::IoError,"CLI_OUTPUT_CLOSE");
        if (Digest(argv[3])!=artifact.sha256) return 97;
        runtime.ReleaseArtifact(artifact.internalRef); runtime.Shutdown();
        std::cout<<"probe/execute/release/copy/hash passed\n"; return 0;
    } catch (const hdm::BridgeProblem& problem) { std::cerr<<problem.what()<<'\n'; return static_cast<int>(problem.code); }
    catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 96; }
}
