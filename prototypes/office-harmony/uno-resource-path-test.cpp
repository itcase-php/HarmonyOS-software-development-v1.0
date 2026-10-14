// Host regression for the OHOS resource-directory branch, not an engine runtime test.
#include <com/sun/star/uno/DeploymentException.hpp>
#include <rtl/ustring.hxx>
#include <cstdlib>
#include <string>
namespace cppu { OUString getUnoIniUri(); }
int main(int argc,char** argv) {
    if (argc!=2) return 64;
    const std::string mode=argv[1];
    if (mode=="valid") setenv("LO_OFFICE_PROGRAM_URL","file:///sandbox/office/program",1);
    else if (mode=="invalid") setenv("LO_OFFICE_PROGRAM_URL","/sandbox/office/program",1);
    else if (mode=="missing") unsetenv("LO_OFFICE_PROGRAM_URL");
    else return 64;
    try {
        const auto uri=cppu::getUnoIniUri();
        return mode=="valid" && uri==u"file:///sandbox/office/program/unorc"_ustr?0:1;
    } catch (const com::sun::star::uno::DeploymentException& error) {
        return mode!="valid" && error.Message.indexOf(u"LO_OFFICE_PROGRAM_URL"_ustr)>=0?0:2;
    }
}
