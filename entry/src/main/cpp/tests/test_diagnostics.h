#pragma once
#if defined(_MSC_VER) && defined(_DEBUG)
#include <crtdbg.h>
#include <rtcapi.h>
#include <cstdlib>
#include <cstdio>
#include <cstdarg>
// Keep /RTC and debug CRT checks enabled, but fail unattended tests in stderr
// instead of showing modal dialogs on the developer's desktop.
inline int NativeTestRuntimeFailure(int,const char* file,int line,const char*,const char* format,...) {
    std::fprintf(stderr,"Native test runtime check failed: %s:%d\n",file?file:"unknown",line);
    va_list args;va_start(args,format);std::vfprintf(stderr,format,args);va_end(args);
    std::fputc('\n',stderr);std::abort();
}
inline void ConfigureNativeTestDiagnostics() {
    _set_error_mode(_OUT_TO_STDERR);
    _set_abort_behavior(0,_WRITE_ABORT_MSG|_CALL_REPORTFAULT);
    for (int type:{_CRT_WARN,_CRT_ERROR,_CRT_ASSERT}) {
        _CrtSetReportMode(type,_CRTDBG_MODE_FILE);_CrtSetReportFile(type,_CRTDBG_FILE_STDERR);
    }
    _RTC_SetErrorFunc(NativeTestRuntimeFailure);
}
#else
inline void ConfigureNativeTestDiagnostics() {}
#endif
