// Isolated device harness: controlled fixtures only, not linked to the converter.
#include <napi/native_api.h>
#include <LibreOfficeKit/LibreOfficeKit.h>
#include <com/sun/star/uno/Exception.hdl>
#include <com/sun/star/uno/DeploymentException.hdl>
#include <dlfcn.h>
#include <cstdlib>
#include <cstdio>
#include <memory>
#include <string>
#include <chrono>
#include <fstream>
#include <iterator>
#include <cxxabi.h>
#include <cstring>
#include <sys/resource.h>

namespace {
struct Work { napi_deferred deferred{}; napi_async_work work{}; std::string root, result, error; };
void SetBootstrapPath(const std::string& path,const std::string& key,const std::string& value) {
    std::ifstream input(path);
    std::string content((std::istreambuf_iterator<char>(input)),std::istreambuf_iterator<char>());
    const auto start=content.find(key+"=");
    if (start==std::string::npos) throw std::runtime_error("BOOTSTRAP_KEY_MISSING: "+key);
    const auto end=content.find('\n',start);
    content.replace(start,end==std::string::npos?content.size()-start:end-start,key+"="+value);
    std::ofstream output(path,std::ios::trunc); output<<content;
    if (!output) throw std::runtime_error("BOOTSTRAP_WRITE_FAILED");
}
void Execute(napi_env, void* data) noexcept {
    auto& work=*static_cast<Work*>(data);
    std::string phase="prepare";
    try {
        const auto started=std::chrono::steady_clock::now();
        (void)freopen((work.root+"/engine-stderr.log").c_str(),"a",stderr);
        setenv("SAL_USE_VCLPLUGIN","svp",1);
        setenv("URE_BOOTSTRAP",("file://"+work.root+"/program/fundamentalrc").c_str(),1);
        setenv("LO_OFFICE_PROGRAM_URL",("file://"+work.root+"/program").c_str(),1);
        setenv("FONTCONFIG_FILE",(work.root+"/fonts.conf").c_str(),1);
        // UNO exceptions cross shared-library boundaries; expose harness RTTI before loading the engine.
        if (!dlopen("liboffice_probe.so",RTLD_NOW|RTLD_GLOBAL))
            throw std::runtime_error("PROBE_GLOBAL_LOAD_FAILED");
        phase="dlopen";
        void* library=dlopen("libsofficeapp.so",RTLD_NOW|RTLD_GLOBAL);
        if (!library) { work.error=std::string("DLOPEN: ")+dlerror(); return; }
        using Initialize=LibreOfficeKit*(*)(const char*,const char*);
        const auto initialize=reinterpret_cast<Initialize>(dlsym(library,"libreofficekit_hook_2"));
        if (!initialize) { work.error="LOK_HOOK_MISSING"; return; }
        Dl_info location{};
        if (!dladdr(reinterpret_cast<void*>(initialize),&location) || !location.dli_fname)
            throw std::runtime_error("LOK_LIBRARY_LOCATION_MISSING");
        const std::string libraryPath=location.dli_fname;
        const auto nativeDirectory="file://"+libraryPath.substr(0,libraryPath.find_last_of('/'));
        fprintf(stderr,"NATIVE_LIBRARY_DIR=%s\n",nativeDirectory.c_str()); fflush(stderr);
        SetBootstrapPath(work.root+"/program/fundamentalrc","LO_LIB_DIR",nativeDirectory);
        SetBootstrapPath(work.root+"/program/unorc","URE_INTERNAL_LIB_DIR",nativeDirectory);
        const auto profile="file://"+work.root+"/profile";
        phase="initialize";
        auto* office=initialize((work.root+"/program").c_str(),profile.c_str());
        if (!office) { work.error="LOK_INITIALIZATION_FAILED"; return; }
        work.result="INITIALIZED\n";
        for (const char* extension : {"docx","pptx"}) {
            phase=std::string("load_")+extension;
            const auto input="file://"+work.root+"/layout."+extension;
            auto* document=office->pClass->documentLoadWithOptions(office,input.c_str(),"EnableMacrosExecution=false");
            if (!document) {
                char* detail=office->pClass->getError(office);
                work.error=std::string("LOAD_")+extension+": "+(detail?detail:"");
                if (detail) office->pClass->freeError(detail);
                break;
            }
            const auto output="file://"+work.root+"/"+extension+"-output.pdf";
            phase=std::string("export_")+extension;
            const auto saved=document->pClass->saveAs(document,output.c_str(),"pdf",nullptr);
            document->pClass->destroy(document);
            if (!saved) { work.error=std::string("EXPORT_")+extension; break; }
            work.result+=std::string(extension)+"_PDF_EXPORTED\n";
        }
        office->pClass->destroy(office);
        rusage usage{}; getrusage(RUSAGE_SELF,&usage);
        work.result+="elapsedMs="+std::to_string(std::chrono::duration<double,std::milli>(
            std::chrono::steady_clock::now()-started).count())+" peakKiB="+std::to_string(usage.ru_maxrss);
    } catch (const com::sun::star::uno::DeploymentException& error) {
        work.error="UNO at "+phase+": ";
        for (int index=0;index<error.Message.getLength();++index) {
            const auto character=error.Message.getStr()[index];
            work.error+=character<128?static_cast<char>(character):'?';
        }
    } catch (const std::exception& error) { work.error=error.what(); }
    catch (...) {
        const auto* type=__cxxabiv1::__cxa_current_exception_type();
        work.error="LOK_PROBE_EXCEPTION at "+phase+": "+(type?type->name():"unknown");
        // Diagnostic only: OHOS can keep RTTI copies in distinct linker scopes.
        // Read only the exact pinned UNO exception type through libc++abi's primary-object API.
        if (type && std::strcmp(type->name(),typeid(com::sun::star::uno::DeploymentException).name())==0) {
            void* primary=__cxxabiv1::__cxa_current_primary_exception();
            if (primary) {
                const auto& exception=*static_cast<const com::sun::star::uno::DeploymentException*>(primary);
                work.error+=" MESSAGE=";
                for (int index=0;index<exception.Message.getLength();++index) {
                    const auto character=exception.Message.getStr()[index];
                    work.error+=character<128?static_cast<char>(character):'?';
                }
                __cxxabiv1::__cxa_decrement_exception_refcount(primary);
            }
        }
    }
    fflush(stderr);
}
void Complete(napi_env env,napi_status status,void* data) {
    std::unique_ptr<Work> work(static_cast<Work*>(data));
    if (status!=napi_ok) work->error="LOK_ASYNC_FAILED";
    napi_value value{};
    const auto& message=work->error.empty()?work->result:work->error;
    napi_create_string_utf8(env,message.c_str(),message.size(),&value);
    if (work->error.empty()) napi_resolve_deferred(env,work->deferred,value);
    else napi_reject_deferred(env,work->deferred,value);
    napi_delete_async_work(env,work->work);
}
napi_value Run(napi_env env,napi_callback_info info) {
    auto work=std::make_unique<Work>();
    size_t count=1,length{}; napi_value argument{},promise{},name{};
    if (napi_get_cb_info(env,info,&count,&argument,nullptr,nullptr)!=napi_ok || count!=1 ||
        napi_get_value_string_utf8(env,argument,nullptr,0,&length)!=napi_ok || !length || length>4096) {
        napi_throw_type_error(env,nullptr,"PROBE_ROOT"); return nullptr;
    }
    work->root.resize(length+1);
    napi_get_value_string_utf8(env,argument,work->root.data(),work->root.size(),&length); work->root.resize(length);
    if (work->root[0]!='/' || work->root.find("..")!=std::string::npos) {
        napi_throw_type_error(env,nullptr,"PROBE_ROOT"); return nullptr;
    }
    napi_create_promise(env,&work->deferred,&promise);
    napi_create_string_utf8(env,"OfficeDeviceProbe",NAPI_AUTO_LENGTH,&name);
    napi_create_async_work(env,nullptr,name,Execute,Complete,work.get(),&work->work);
    napi_queue_async_work(env,work->work); work.release(); return promise;
}
napi_value Init(napi_env env,napi_value exports) {
    napi_property_descriptor descriptor={"run",nullptr,Run,nullptr,nullptr,nullptr,napi_default,nullptr};
    napi_define_properties(env,exports,1,&descriptor); return exports;
}
napi_module module={1,0,nullptr,Init,"office_probe",nullptr,{nullptr}};
}
extern "C" __attribute__((constructor)) void RegisterOfficeProbe() { napi_module_register(&module); }
