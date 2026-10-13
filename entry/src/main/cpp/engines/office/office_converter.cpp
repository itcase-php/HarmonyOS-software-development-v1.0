#include "../../core/converter.h"
#include "../../production/office_context.h"
#include "../../production/office_input.h"
#include "../../production/route_policy.h"
#include "../../generated/office_bundle.h"
#include "../../napi/bridge_problem.h"
#include "hdm_build_manifest.h"
#include <fstream>
#include <mutex>
#include <set>
#include <algorithm>
#if defined(__OHOS__) && defined(__aarch64__) && defined(HDM_BUNDLED_OFFICE)
#include <LibreOfficeKit/LibreOfficeKit.h>
#include <dlfcn.h>
#include <cstdlib>
#define HDM_CAN_LOAD_OFFICE 1
#endif

namespace hdm {
namespace {
std::mutex officeMutex;
Status Failure(ErrorCode code,const char* reason) {
    Status status; status.code=code; status.reason=reason; status.module="office";
    status.messageKey=std::string("errors.")+ErrorCodeName(code); return status;
}
#ifdef HDM_CAN_LOAD_OFFICE
// LOK is process-global and must never be initialized/destroyed for each document.
LibreOfficeKit* office{};
std::string runtimeRoot;
std::string Url(const std::string& path) {
    static const char hex[]="0123456789ABCDEF"; std::string url="file://";
    for (unsigned char c:path) {
        if ((c>='a'&&c<='z') || (c>='A'&&c<='Z') || (c>='0'&&c<='9') || c=='/' || c=='-' || c=='_' || c=='.') url+=c;
        else { url+='%'; url+=hex[c>>4]; url+=hex[c&15]; }
    } return url;
}
void Bootstrap(const std::string& path,const std::string& key,const std::string& value) {
    std::ifstream input(path); std::string text((std::istreambuf_iterator<char>(input)),{});
    const auto start=text.find(key+"=");
    if (start==std::string::npos) throw BridgeProblem(ErrorCode::EngineMissing,"OFFICE_BOOTSTRAP_KEY_MISSING");
    const auto end=text.find('\n',start); text.replace(start,end==std::string::npos?text.size()-start:end-start,key+"="+value);
    std::ofstream output(path,std::ios::trunc); output<<text;
    if (!output) throw BridgeProblem(ErrorCode::IoError,"OFFICE_BOOTSTRAP_WRITE");
}
std::string Fold(std::string value) {
    std::transform(value.begin(),value.end(),value.begin(),[](unsigned char c){ return c<128?static_cast<char>(std::tolower(c)):static_cast<char>(c); });
    return value;
}
std::vector<std::string> CheckFonts(const std::vector<std::string>& required,const ContentExpectation& content) {
    // Exact family inventory, no FcFontMatch fallback which could silently substitute.
    struct FontSet { int count,size; void** fonts; };
    void* library=dlopen("libfontconfig-lo.so.1.16.1",RTLD_NOW|RTLD_LOCAL);
    if (!library) throw BridgeProblem(ErrorCode::EngineMissing,"OFFICE_FONTCONFIG_MISSING");
    const auto create=reinterpret_cast<void*(*)()>(dlsym(library,"FcPatternCreate"));
    const auto objects=reinterpret_cast<void*(*)(const char*,...)>(dlsym(library,"FcObjectSetBuild"));
    const auto list=reinterpret_cast<FontSet*(*)(void*,void*,void*)>(dlsym(library,"FcFontList"));
    const auto get=reinterpret_cast<int(*)(const void*,const char*,int,unsigned char**)>(dlsym(library,"FcPatternGetString"));
    const auto charset=reinterpret_cast<int(*)(const void*,const char*,int,void**)>(dlsym(library,"FcPatternGetCharSet"));
    const auto contains=reinterpret_cast<int(*)(const void*,std::uint32_t)>(dlsym(library,"FcCharSetHasChar"));
    const auto freePattern=reinterpret_cast<void(*)(void*)>(dlsym(library,"FcPatternDestroy"));
    const auto freeObjects=reinterpret_cast<void(*)(void*)>(dlsym(library,"FcObjectSetDestroy"));
    const auto freeSet=reinterpret_cast<void(*)(FontSet*)>(dlsym(library,"FcFontSetDestroy"));
    if (!create || !objects || !list || !get || !charset || !contains || !freePattern || !freeObjects || !freeSet) {
        dlclose(library);
        throw BridgeProblem(ErrorCode::EngineMissing,"OFFICE_FONTCONFIG_API");
    }
    void* pattern=create(); void* fields=objects("family","charset",nullptr);
    FontSet* set=list(nullptr,pattern,fields); std::set<std::string> available;
    if (set) for (int index=0;index<set->count;++index) for (int alias=0;;++alias) {
        unsigned char* name{}; if (get(set->fonts[index],"family",alias,&name)!=0) break;
        if (name) available.insert(Fold(reinterpret_cast<char*>(name)));
    }
    bool missingGlyph=false;
    for (const auto& entry:content.textMinimum) {
        bool covered=false;
        if (set) for (int index=0;index<set->count && !covered;++index) {
            void* characters{};
            if (charset(set->fonts[index],"charset",0,&characters)==0 && characters)
                covered=contains(characters,entry.first)!=0;
        }
        missingGlyph|=!covered;
    }
    if (set) freeSet(set); if (fields) freeObjects(fields); if (pattern) freePattern(pattern);
    dlclose(library);
    if (available.empty()) throw BridgeProblem(ErrorCode::FontMissing,"OFFICE_FONT_INVENTORY_EMPTY");
    if (missingGlyph) throw BridgeProblem(ErrorCode::FontMissing,"OFFICE_GLYPH_MISSING");
    std::vector<std::string> missing;
    for (const auto& name:required) if (!available.count(Fold(name))) missing.push_back(name);
    return missing;
}
#endif
class OfficeConverter final : public IConverter {
    std::string root_;
    ResourceBudget budget_{};
public:
    ConverterCapabilities Describe() const override {
        ConverterCapabilities caps; caps.engine={"office","LibreOffice-26.2.6.2-ohos-experimental",kOfficeBuildHash};
#ifdef HDM_CAN_LOAD_OFFICE
        caps.decoderIds={"writer-docx","impress-pptx"}; caps.encoderIds={"writer-impress-pdf-export"};
        caps.inputSubsetIds={"ooxml-unprotected-local-no-active-content-fonts-present-v1"};
        caps.available=production::IsProductRouteExecutable("docx-pdf");
#endif
        return caps;
    }
    Status Initialize(const EngineInitContext& init) override {
        if (init.offlineResourceRootRef.empty()) return Failure(ErrorCode::EngineMissing,"OFFICE_RESOURCES_MISSING");
        root_=init.offlineResourceRootRef; budget_=init.hardLimits;
#ifdef HDM_CAN_LOAD_OFFICE
        std::lock_guard<std::mutex> lock(officeMutex);
        try {
            if (office) return root_==runtimeRoot?Status{}:Failure(ErrorCode::TaskBusy,"OFFICE_RUNTIME_ROOT_CHANGED");
            if (!std::filesystem::is_regular_file(root_+"/ready.sha256")) return Failure(ErrorCode::EngineMissing,"OFFICE_RESOURCES_NOT_READY");
            std::ifstream ready(root_+"/ready.sha256"); std::string readyHash;
            std::getline(ready,readyHash);
            if (readyHash!=kOfficeBundleHash) return Failure(ErrorCode::EngineMissing,"OFFICE_RESOURCE_VERSION_MISMATCH");
            setenv("SAL_USE_VCLPLUGIN","svp",1);
            setenv("URE_BOOTSTRAP",Url(root_+"/program/fundamentalrc").c_str(),1);
            setenv("LO_OFFICE_PROGRAM_URL",Url(root_+"/program").c_str(),1);
            setenv("FONTCONFIG_FILE",(root_+"/fonts.conf").c_str(),1);
            void* library=dlopen("libsofficeapp.so",RTLD_NOW|RTLD_GLOBAL);
            if (!library) return Failure(ErrorCode::EngineMissing,"OFFICE_LIBRARY_LOAD_FAILED");
            using Hook=LibreOfficeKit*(*)(const char*,const char*);
            const auto hook=reinterpret_cast<Hook>(dlsym(library,"libreofficekit_hook_2")); Dl_info location{};
            if (!hook || !dladdr(reinterpret_cast<void*>(hook),&location) || !location.dli_fname)
                return Failure(ErrorCode::EngineMissing,"OFFICE_LOK_HOOK_MISSING");
            const std::filesystem::path lib=location.dli_fname;
            Bootstrap(root_+"/program/fundamentalrc","LO_LIB_DIR",Url(lib.parent_path().string()));
            Bootstrap(root_+"/program/unorc","URE_INTERNAL_LIB_DIR",Url(lib.parent_path().string()));
            auto* initialized=hook((root_+"/program").c_str(),Url(root_+"/profile").c_str());
            if (!initialized || !LIBREOFFICEKIT_HAS(initialized,documentLoadWithOptions))
                return Failure(ErrorCode::EngineMissing,"OFFICE_INITIALIZATION_FAILED");
            office=initialized;
            runtimeRoot=root_; return {};
        } catch (const BridgeProblem& problem) { return Failure(problem.code,problem.what()); }
        catch (...) { return Failure(ErrorCode::EngineMissing,"OFFICE_INITIALIZATION_EXCEPTION"); }
#else
        return Failure(ErrorCode::AbiUnsupported,"OFFICE_ARM64_ONLY");
#endif
    }
    Status Validate(const ConvertRequest& request,const TaskContext& context) const override {
        if (!dynamic_cast<const production::OfficeContext*>(&context) || request.inputs.size()!=1 || request.targetFormatId!="pdf" ||
            (request.inputs[0].sourceFormatId!="docx" && request.inputs[0].sourceFormatId!="pptx") ||
            request.plan.routeId!=request.inputs[0].sourceFormatId+"-pdf" || request.operation!=Operation::Convert)
            return Failure(ErrorCode::UnsupportedFormat,"OFFICE_ROUTE_UNSUPPORTED");
        return {};
    }
    Status Execute(const ConvertRequest& request,TaskContext& context) override {
        auto* task=dynamic_cast<production::OfficeContext*>(&context);
        if (!task) return Failure(ErrorCode::InvalidRequest,"OFFICE_CONTEXT_REQUIRED");
#ifdef HDM_CAN_LOAD_OFFICE
        std::lock_guard<std::mutex> lock(officeMutex);
        if (!office || runtimeRoot!=root_) return Failure(ErrorCode::EngineMissing,"OFFICE_NOT_INITIALIZED");
        try {
            auto status=task->CheckBudgetAndDeadline(); if (!status.IsOk()) return status;
            const auto inspected=production::InspectOffice(task->input,request.inputs[0].sourceFormatId,budget_);
            task->content=inspected.content;
            task->missingFonts=CheckFonts(inspected.fonts,inspected.content);
            if (!task->missingFonts.empty() && inspected.hasPrivateGlyphs)
                return Failure(ErrorCode::FontMissing,"OFFICE_SYMBOL_FONT_MISSING");
            if (!task->missingFonts.empty() && (!request.options.office || request.options.office->missingFontPolicy!="approved_fallback"))
                return Failure(ErrorCode::FontMissing,"OFFICE_REQUIRED_FONT_MISSING");
            auto* document=office->pClass->documentLoadWithOptions(office,Url(task->input.string()).c_str(),"Batch=true,EnableMacrosExecution=false");
            if (!document) return Failure(ErrorCode::FileCorrupted,"OFFICE_DOCUMENT_LOAD_FAILED");
            struct Cleanup { LibreOfficeKitDocument* doc; ~Cleanup(){doc->pClass->destroy(doc);} } cleanup{document};
            const int expected=request.inputs[0].sourceFormatId=="docx"?0:2;
            if (document->pClass->getDocumentType(document)!=expected)
                return Failure(ErrorCode::UnsupportedFormat,"OFFICE_DOCUMENT_TYPE_MISMATCH");
            status=task->CheckBudgetAndDeadline(); if (!status.IsOk()) return status;
            if (!document->pClass->saveAs(document,Url(task->output.string()).c_str(),"pdf",nullptr))
                return Failure(ErrorCode::IoError,"OFFICE_PDF_EXPORT_FAILED");
            status=task->CheckBudgetAndDeadline(); if (!status.IsOk()) return status;
            task->bytes=std::filesystem::file_size(task->output);
            if (!task->bytes || task->bytes>budget_.maxTempBytes)
                return Failure(ErrorCode::ResourceLimitExceeded,"OFFICE_OUTPUT_LIMIT");
            return {};
        } catch (const BridgeProblem& problem) { return Failure(problem.code,problem.what()); }
        catch (const std::bad_alloc&) { return Failure(ErrorCode::ResourceLimitExceeded,"OFFICE_ALLOCATION_FAILED"); }
        catch (...) { return Failure(ErrorCode::InternalError,"OFFICE_CONVERSION_EXCEPTION"); }
#else
        (void)request; return Failure(ErrorCode::AbiUnsupported,"OFFICE_ARM64_ONLY");
#endif
    }
    Result<CandidateOutput> CollectOutput(TaskContext& context) override {
        auto* task=dynamic_cast<production::OfficeContext*>(&context);
        if (!task || !task->bytes) return {Failure(ErrorCode::OutputValidationFailed,"OFFICE_OUTPUT_MISSING"),std::nullopt};
        CandidateOutput output; output.files.push_back({"primary","pdf",task->relative,task->bytes,std::nullopt});
        return {{},std::move(output)};
    }
    void Release() noexcept override { root_.clear(); }
};
}
std::unique_ptr<IConverter> CreateOfficeConverter() { return std::make_unique<OfficeConverter>(); }
}
