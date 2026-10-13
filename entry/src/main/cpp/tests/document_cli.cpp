#include "../production/runtime.h"
#include "../production/office_input.h"
#include "../production/sha256.h"
#include "../generated/registry_metadata.h"
#include "../napi/bridge_problem.h"
#include <array>
#include <fstream>
#include <iostream>
#include <chrono>
namespace fs=std::filesystem;
std::string Digest(const fs::path& path) {
    hdm::production::Sha256 digest; std::ifstream file(path,std::ios::binary); std::array<char,65536> buffer{};
    while (file) { file.read(buffer.data(),buffer.size()); digest.Update(buffer.data(),static_cast<std::size_t>(file.gcount())); }
    return digest.FinalHex();
}
int main(int argc,char** argv) {
    if (argc<3) return 99;
    hdm::ResourceBudget budget{104857600,314572800,201326592,536870912,300,16000000,2,180000};
    try {
        const std::string format=argv[1];
        if (format=="docx" || format=="pptx") {
            const auto input=hdm::production::InspectOffice(argv[2],format,budget);
            std::uint64_t characters{};for(const auto& item:input.content.textMinimum)characters+=item.second;
            std::cout<<"slides="<<input.slides<<" fonts="<<input.fonts.size()<<" characters="<<characters
                <<" images="<<input.content.minimumImages<<" private="<<input.hasPrivateGlyphs<<'\n';return 0;
        }
        if (argc!=4) return 99;
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
        fs::copy_file(cache/"artifacts"/(artifact.artifactId+".pdf"),argv[3],fs::copy_options::overwrite_existing);
        if (Digest(argv[3])!=artifact.sha256) return 97;
        runtime.ReleaseArtifact(artifact.internalRef); runtime.ReleaseTask(task,attempt); runtime.Shutdown();
        std::cout<<"probe/execute/commit/hash/release passed\n"; return 0;
    } catch (const hdm::BridgeProblem& problem) { std::cerr<<problem.what()<<'\n'; return static_cast<int>(problem.code); }
    catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 96; }
}
