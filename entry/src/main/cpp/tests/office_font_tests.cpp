#include "../production/office_font_usage.h"
#include <stdexcept>
#include <iostream>
using namespace hdm;
using namespace hdm::production;
void Require(bool value,const char* message) {if (!value) throw std::runtime_error(message);}
int main() {
    try {
        const auto available=[](const std::string& name) {return name=="Installed" || name=="Icon";};
        const auto glyph=[](const std::string& name,std::uint32_t cp) {return cp<0xe000 || (name=="Icon" && cp==0xe001);};
        std::vector<FontDiagnostic> diagnostics;
        const OfficeFontUse present{"Installed","word/document.xml",{'A'},false};
        const OfficeFontUse absent{"Missing","word/header1.xml",{'A'},false};
        const OfficeFontUse icon{"Icon","word/document.xml",{0xe001},false};
        Require(ValidateOfficeFontUsage({present},available,glyph,false,diagnostics).IsOk(),"default rejects installed family");
        Require(diagnostics.empty(),"installed family reported as missing");
        Require(ValidateOfficeFontUsage({absent},available,glyph,false,diagnostics).reason=="OFFICE_REQUIRED_FONT_MISSING","unapproved fallback accepted");
        Require(diagnostics.size()==1 && diagnostics[0].family=="Missing" && diagnostics[0].part=="word/header1.xml","missing family/part lost");
        Require(ValidateOfficeFontUsage({absent},available,glyph,true,diagnostics).IsOk(),"approved ordinary fallback rejected");
        Require(!diagnostics.empty(),"approved fallback not reported");
        Require(ValidateOfficeFontUsage({absent,icon},available,glyph,true,diagnostics).IsOk(),"unrelated normal font falsely blocks installed icon");
        const OfficeFontUse missingIcon{"Missing","word/document.xml",{0xe001},false};
        for (bool approved:{false,true}) Require(ValidateOfficeFontUsage({missingIcon},available,glyph,approved,diagnostics).reason=="OFFICE_SYMBOL_FONT_MISSING","private icon silently substituted");
        const OfficeFontUse unmapped{"Installed","word/document.xml",{0xe002},true};
        Require(ValidateOfficeFontUsage({unmapped},available,glyph,true,diagnostics).reason=="OFFICE_SYMBOL_FONT_MISSING","symbol coverage not bound to font");
        const auto noGlyph=[](const std::string&,std::uint32_t){return false;};
        Require(ValidateOfficeFontUsage({present},available,noGlyph,true,diagnostics).reason=="OFFICE_GLYPH_MISSING","missing ordinary glyph accepted");
        std::cout<<"9 font policy cases passed; no device/fontconfig execution\n";return 0;
    } catch (const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
}
