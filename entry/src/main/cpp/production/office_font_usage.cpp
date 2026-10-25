#include "office_font_usage.h"
#include "../napi/bridge_problem.h"
#include <tinyxml2.h>
#include <array>
#include <algorithm>
#include <set>
#include <memory>
#include <cstring>

namespace hdm::production {
namespace {
using E=tinyxml2::XMLElement;
std::string Local(const char* name) {
    const std::string text=name?name:""; const auto colon=text.find(':');
    return text.substr(colon==std::string::npos?0:colon+1);
}
std::string Attr(E* node,const char* key) {
    if (node) for (auto* a=node->FirstAttribute();a;a=a->Next()) if (Local(a->Name())==key) return a->Value();
    return {};
}
E* Child(E* node,const char* name) {
    if (node) for (auto* e=node->FirstChildElement();e;e=e->NextSiblingElement()) if (Local(e->Name())==name) return e;
    return nullptr;
}
E* Desc(E* node,const char* name) {
    if (!node) return nullptr;
    if (Local(node->Name())==name) return node;
    for (auto* e=node->FirstChildElement();e;e=e->NextSiblingElement()) if (auto* found=Desc(e,name)) return found;
    return nullptr;
}
[[noreturn]] void Unresolved() { throw BridgeProblem(ErrorCode::UnsupportedFeature,"OFFICE_FONT_USAGE_UNRESOLVED"); }
bool On(E* e) { const auto value=Attr(e,"val");return e && value!="0" && value!="false" && value!="off"; }
bool Private(std::uint32_t cp) { return (cp>=0xe000 && cp<=0xf8ff) || (cp>=0xf0000 && cp<=0x10fffd); }
bool Ignore(std::uint32_t cp) {
    return cp<=32 || cp==0xa0 || cp==0xad || (cp>=0x2000 && cp<=0x200f) ||
        (cp>=0x2028 && cp<=0x202f) || (cp>=0x2060 && cp<=0x206f) || cp==0xfeff;
}
std::vector<std::uint32_t> Characters(const std::string& text) {
    std::vector<std::uint32_t> result;
    for (std::size_t i=0;i<text.size();) {
        const auto first=static_cast<unsigned char>(text[i++]); std::uint32_t cp=first;unsigned more=0;
        if (first>=0xc2 && first<=0xdf) {cp&=31;more=1;}
        else if (first>=0xe0 && first<=0xef) {cp&=15;more=2;}
        else if (first>=0xf0 && first<=0xf4) {cp&=7;more=3;}
        else if (first>=128) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
        if (i+more>text.size()) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
        for (unsigned j=0;j<more;++j) {
            const auto next=static_cast<unsigned char>(text[i++]);
            if ((next&0xc0)!=0x80) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
            cp=(cp<<6)|(next&63);
        }
        if ((more==1 && cp<128) || (more==2 && cp<2048) || (more==3 && cp<65536) ||
            cp>0x10ffff || (cp>=0xd800 && cp<=0xdfff)) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
        result.push_back(cp);
    }
    return result;
}
// Slots are ascii, hAnsi, eastAsia, complex script. Empty means the application's
// default, not an absent declared font. A theme token must resolve explicitly.
struct Spec {
    std::array<std::string,4> names{};
    std::array<bool,4> themed{};
    std::string eastLanguage,hint;
    bool complex{};
};
void WordProps(E* props,Spec& out) {
    if (!props) return;
    if (auto* fonts=Child(props,"rFonts")) {
        const char* slots[]={"ascii","hAnsi","eastAsia","cs"};
        const char* themes[]={"asciiTheme","hAnsiTheme","eastAsiaTheme","cstheme"};
        for (unsigned i=0;i<4;++i) {
            const auto direct=Attr(fonts,slots[i]),theme=Attr(fonts,themes[i]);
            if (!direct.empty() || !theme.empty()) {out.names[i]=theme.empty()?direct:theme;out.themed[i]=!theme.empty();}
        }
        const auto hint=Attr(fonts,"hint");if (!hint.empty()) out.hint=hint;
    }
    const auto language=Attr(Child(props,"lang"),"eastAsia");if (!language.empty()) out.eastLanguage=language;
    if (Child(props,"cs")) out.complex=On(Child(props,"cs"));
    if (Child(props,"rtl")) out.complex=On(Child(props,"rtl"));
}
void DrawingProps(E* props,Spec& out) {
    const char* slots[]={"latin","latin","ea","cs"};
    for (unsigned i=0;i<4;++i) {
        const auto name=Attr(Child(props,slots[i]),"typeface");
        if (!name.empty()) {out.names[i]=name;out.themed[i]=name[0]=='+';}
    }
    const auto lang=Attr(props,"lang");if (!lang.empty()) out.eastLanguage=lang;
}
unsigned Slot(std::uint32_t cp,const Spec& spec) {
    if (spec.complex) return 3;
    if ((cp>=0x0590 && cp<=0x109f) || (cp>=0x1780 && cp<=0x18af) || (cp>=0xfb1d && cp<=0xfdff) ||
        (cp>=0xfe70 && cp<=0xfeff)) return 3;
    if ((cp>=0x1100 && cp<=0x11ff) || (cp>=0x2e80 && cp<=0xa4cf) || (cp>=0xac00 && cp<=0xd7af) ||
        (cp>=0xf900 && cp<=0xfaff) || (cp>=0xfe30 && cp<=0xfe6f) || (cp>=0xff00 && cp<=0xffef) ||
        (cp>=0x20000 && cp<=0x323af) || (spec.hint=="eastAsia" && cp>=0x2000 && cp<=0x27ff)) return 2;
    return cp<128?0:1;
}
std::string Script(std::uint32_t cp,const Spec& spec) {
    if ((cp>=0x3040 && cp<=0x30ff) || spec.eastLanguage.rfind("ja",0)==0) return "Jpan";
    if ((cp>=0xac00 && cp<=0xd7af) || spec.eastLanguage.rfind("ko",0)==0) return "Hang";
    if (cp>=0x2e80 && cp<=0x323af) return spec.eastLanguage=="zh-TW" || spec.eastLanguage=="zh-HK" || spec.eastLanguage=="zh-MO"?"Hant":"Hans";
    if (cp>=0x0590 && cp<=0x05ff) return "Hebr";
    if ((cp>=0x0600 && cp<=0x08ff) || (cp>=0xfb50 && cp<=0xfeff)) return "Arab";
    const std::pair<std::uint32_t,const char*> blocks[]={{0x0900,"Deva"},{0x0980,"Beng"},{0x0a00,"Guru"},{0x0a80,"Gujr"},
        {0x0b00,"Orya"},{0x0b80,"Taml"},{0x0c00,"Telu"},{0x0c80,"Knda"},{0x0d00,"Mlym"},{0x0d80,"Sinh"},{0x0e00,"Thai"},{0x0e80,"Laoo"}};
    for (const auto& block:blocks) if (cp>=block.first && cp<block.first+0x80) return block.second;
    return {};
}
class Usage {
    const std::map<std::string,std::string>& parts_;
    std::map<std::string,std::unique_ptr<tinyxml2::XMLDocument>> documents_;
    std::map<std::string,E*> styles_;
    std::map<std::string,OfficeFontUse> uses_;
    std::map<std::uint32_t,std::uint32_t> text_;
    OfficeInput& result_;
    std::string defaultStyle_,defaultCharacter_,wordTheme_;
    std::string themeLanguage_;
    bool evenHeaders_{};
    E* defaults_{};
    std::set<std::string> visited_;
    std::uint64_t characters_{};
public:
    Usage(const std::map<std::string,std::string>& parts,OfficeInput& result):parts_(parts),result_(result) {}
    E* Root(const std::string& part) {
        if (part.empty()) return nullptr;
        auto it=documents_.find(part);
        if (it!=documents_.end()) return it->second->RootElement();
        const auto input=parts_.find(part);if (input==parts_.end()) Unresolved();
        auto doc=std::make_unique<tinyxml2::XMLDocument>();
        if (doc->Parse(input->second.data(),input->second.size())!=tinyxml2::XML_SUCCESS) Unresolved();
        auto* root=doc->RootElement();documents_.emplace(part,std::move(doc));return root;
    }
    std::string Related(const std::string& part,const std::string& type,const std::string& id={}) {
        const auto slash=part.find_last_of('/');const auto base=part.substr(0,slash+1);
        const auto rel=base+"_rels/"+part.substr(slash+1)+".rels";
        if (!parts_.count(rel)) {if (!id.empty()) Unresolved();return {};}
        std::string found;
        for (auto* e=Root(rel)->FirstChildElement();e;e=e->NextSiblingElement()) {
            const auto kind=Attr(e,"Type");
            if (kind.size()<type.size()+1 || kind.substr(kind.size()-type.size()-1)!="/"+type || (!id.empty() && Attr(e,"Id")!=id)) continue;
            const auto target=Attr(e,"Target");
            const auto joined=(std::filesystem::path(base)/target).lexically_normal().generic_string();
            if (joined.empty() || joined[0]=='/' || joined.rfind("../",0)==0 || !parts_.count(joined) || !found.empty()) Unresolved();
            found=joined;
        }
        if (!id.empty() && found.empty()) Unresolved();
        return found;
    }
    std::string Family(const Spec& spec,std::uint32_t cp,const std::string& theme) {
        const auto slot=Slot(cp,spec);std::string name=spec.names[slot];
        if (name.empty() && slot==1 && !spec.names[0].empty()) name=spec.names[0];
        bool themed=spec.themed[slot] || (!spec.names[0].empty() && slot==1 && spec.names[1].empty() && spec.themed[0]);
        if (themed) {
            if (theme.empty()) Unresolved();
            bool major=name.rfind("major",0)==0 || name.rfind("+mj-",0)==0;
            if (!major && name.rfind("minor",0)!=0 && name.rfind("+mn-",0)!=0) Unresolved();
            const auto role=name.rfind("+m",0)==0?name.substr(4):name.substr(5);
            const unsigned themeSlot=role=="EastAsia" || role=="ea"?2:role=="Bidi" || role=="cs"?3:0;
            if (themeSlot==0 && role!="Ascii" && role!="HAnsi" && role!="lt") Unresolved();
            auto* fonts=Child(Desc(Root(theme),"fontScheme"),major?"majorFont":"minorFont");
            if (!fonts) Unresolved();
            const auto face=Attr(Child(fonts,themeSlot==0?"latin":themeSlot==2?"ea":"cs"),"typeface");
            name=face;
            if (name.empty() && themeSlot>=2) {
                const auto script=Script(cp,spec);if (script.empty()) Unresolved();
                for (auto* font=fonts->FirstChildElement();font;font=font->NextSiblingElement())
                    if (Local(font->Name())=="font" && Attr(font,"script")==script) name=Attr(font,"typeface");
            }
            if (name.empty()) Unresolved();
        }
        if (name.size()>256 || std::any_of(name.begin(),name.end(),[](unsigned char c){return c<32 || c==127;}))
            throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_FONT_LIMIT");
        return name;
    }
    void Add(const std::string& value,const Spec& spec,const std::string& theme,const std::string& part,bool symbol=false,bool content=true) {
        for (const auto cp:Characters(value)) {
            if (Ignore(cp)) continue;
            if (++characters_>1000000 || text_.size()>8192 || uses_.size()>4096)
                throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_TEXT_LIMIT");
            const auto family=Family(spec,cp,theme);
            const auto key=part+'\n'+family+(symbol?"\n1":"\n0");auto& use=uses_[key];
            use.family=family;use.part=part;use.symbol=symbol;use.characters.push_back(cp);
            if (content) ++text_[cp];
            result_.hasPrivateGlyphs|=symbol || Private(cp);
        }
    }
    void Style(const std::string& id,Spec& spec,std::vector<E*>& chain,std::set<std::string>& visiting) {
        if (id.empty()) return;
        const auto found=styles_.find(id);
        if (found==styles_.end() || visiting.size()>=64 || !visiting.insert(id).second) Unresolved();
        auto* e=found->second;Style(Attr(Child(e,"basedOn"),"val"),spec,chain,visiting);
        WordProps(Child(e,"rPr"),spec);chain.push_back(e);visiting.erase(id);
    }
    void Style(const std::string& id,Spec& spec,std::vector<E*>& chain) {std::set<std::string> visiting;Style(id,spec,chain,visiting);}
    void Number(E* paragraph,const std::vector<E*>& chain,Spec spec,const std::string& part) {
        std::string id,level="0";
        const auto read=[&](E* ppr) {
            auto* num=Child(ppr,"numPr");const auto n=Attr(Child(num,"numId"),"val"),l=Attr(Child(num,"ilvl"),"val");
            if (!n.empty()) id=n;if (!l.empty()) level=l;
        };
        for (auto* e:chain) read(Child(e,"pPr"));read(Child(paragraph,"pPr"));
        if (id.empty() || id=="0") return;
        const auto path=Related("word/document.xml","numbering");if (path.empty()) Unresolved();
        E* num=nullptr;E* abstract=nullptr;E* overrideLevel=nullptr;
        for (auto* e=Root(path)->FirstChildElement();e;e=e->NextSiblingElement()) if (Local(e->Name())=="num" && Attr(e,"numId")==id) num=e;
        if (!num) Unresolved();
        const auto abstractId=Attr(Child(num,"abstractNumId"),"val");
        for (auto* e=Root(path)->FirstChildElement();e;e=e->NextSiblingElement()) if (Local(e->Name())=="abstractNum" && Attr(e,"abstractNumId")==abstractId) abstract=e;
        if (!abstract || Child(abstract,"numStyleLink") || Child(abstract,"styleLink")) Unresolved();
        E* lvl=nullptr;
        for (auto* e=abstract->FirstChildElement();e;e=e->NextSiblingElement()) if (Local(e->Name())=="lvl" && Attr(e,"ilvl")==level) lvl=e;
        for (auto* e=num->FirstChildElement();e;e=e->NextSiblingElement()) if (Local(e->Name())=="lvlOverride" && Attr(e,"ilvl")==level) overrideLevel=Child(e,"lvl");
        if (overrideLevel) lvl=overrideLevel;if (!lvl) Unresolved();
        WordProps(Child(lvl,"rPr"),spec);
        const auto format=Attr(Child(lvl,"numFmt"),"val"),label=Attr(Child(lvl,"lvlText"),"val");
        if (format=="none") return;
        if (format=="bullet") Add(label,spec,wordTheme_,part,false,false);
        else {
            std::string digits;
            if (format=="decimal" || format=="decimalZero") digits="0123456789";
            else if (format=="lowerLetter") digits="abcdefghijklmnopqrstuvwxyz";
            else if (format=="upperLetter") digits="ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            else if (format=="lowerRoman") digits="ivxlcdm";
            else if (format=="upperRoman") digits="IVXLCDM";
            else Unresolved();
            std::string expanded;
            for (std::size_t i=0;i<label.size();++i) {
                if (label[i]=='%' && i+1<label.size() && label[i+1]>='1' && label[i+1]<='9') {expanded+=digits;++i;}
                else expanded+=label[i];
            }
            Add(expanded,spec,wordTheme_,part,false,false);
        }
    }
    void WordRuns(E* parent,const Spec& paragraph,const std::string& part) {
        for (auto* e=parent->FirstChildElement();e;e=e->NextSiblingElement()) {
            const auto name=Local(e->Name());
            if (name=="p") {WordParagraph(e,Spec{},part);continue;}
            if (name=="r") {
                Spec spec=paragraph;std::vector<E*> chain;
                auto* props=Child(e,"rPr");const auto style=Attr(Child(props,"rStyle"),"val");
                Style(style.empty()?defaultCharacter_:style,spec,chain);WordProps(props,spec);
                for (auto* item=e->FirstChildElement();item;item=item->NextSiblingElement()) {
                    const auto kind=Local(item->Name());
                    if (kind=="t" && item->GetText()) Add(item->GetText(),spec,wordTheme_,part);
                    else if (kind=="sym") {
                        const auto font=Attr(item,"font"),hex=Attr(item,"char");
                        if (font.empty() || hex.empty() || hex.size()>6 || hex.find_first_not_of("0123456789abcdefABCDEF")!=std::string::npos) Unresolved();
                        const auto cp=static_cast<std::uint32_t>(std::stoul(hex,nullptr,16));if (cp>0x10ffff || (cp>=0xd800 && cp<=0xdfff)) Unresolved();
                        Spec icon;icon.names.fill(font);Family(icon,cp,wordTheme_);const auto key=part+'\n'+font+"\n1";
                        auto& use=uses_[key];use.family=font;use.part=part;use.symbol=true;use.characters.push_back(cp);result_.hasPrivateGlyphs=true;
                    } else if (kind=="footnoteReference" || kind=="endnoteReference") {
                        const auto type=kind=="footnoteReference"?"footnotes":"endnotes",itemType=kind=="footnoteReference"?"footnote":"endnote";
                        const auto notePart=Related("word/document.xml",type),id=Attr(item,"id");if (notePart.empty()) Unresolved();
                        bool found=false;
                        for (auto* note=Root(notePart)->FirstChildElement();note;note=note->NextSiblingElement())
                            if (Local(note->Name())==itemType && Attr(note,"id")==id) {
                                const auto key=notePart+"#"+id;if (visited_.insert(key).second) WordWalk(note,Spec{},notePart);found=true;
                            }
                        if (!found) Unresolved();
                    } else if (kind=="drawing" || kind=="pict") {WordWalk(item,Spec{},part);}
                }
            } else if (name!="pPr") WordRuns(e,paragraph,part);
        }
    }
    void WordParagraph(E* p,const Spec& table,const std::string& part) {
        Spec spec;spec.eastLanguage=themeLanguage_;WordProps(defaults_,spec);
        for (unsigned i=0;i<4;++i) if (!table.names[i].empty()) {spec.names[i]=table.names[i];spec.themed[i]=table.themed[i];}
        std::vector<E*> chain;
        const auto style=Attr(Child(Child(p,"pPr"),"pStyle"),"val");
        Style(style.empty()?defaultStyle_:style,spec,chain);
        Number(p,chain,spec,part);WordRuns(p,spec,part);
    }
    void WordWalk(E* parent,Spec table,const std::string& part) {
        for (auto* e=parent->FirstChildElement();e;e=e->NextSiblingElement()) {
            const auto name=Local(e->Name());
            if (name=="p") WordParagraph(e,table,part);
            else if (name=="headerReference" || name=="footerReference") {
                const auto type=Attr(e,"type");auto* section=e->Parent()?e->Parent()->ToElement():nullptr;
                if ((type=="first" && !On(Child(section,"titlePg"))) || (type=="even" && !evenHeaders_)) continue;
                const auto path=Related(part,name=="headerReference"?"header":"footer",Attr(e,"id"));
                if (!path.empty() && visited_.insert(path).second) WordWalk(Root(path),Spec{},path);
            } else if (name=="tbl") {
                Spec cell;std::vector<E*> chain;const auto id=Attr(Child(Child(e,"tblPr"),"tblStyle"),"val");Style(id,cell,chain);
                for (auto* style:chain) for (auto* condition=style->FirstChildElement();condition;condition=condition->NextSiblingElement())
                    if (Local(condition->Name())=="tblStylePr" && Child(Child(condition,"rPr"),"rFonts")) {
                        if (Attr(condition,"type")!="wholeTable") Unresolved();WordProps(Child(condition,"rPr"),cell);
                    }
                WordWalk(e,cell,part);
            } else if (name=="blip" || name=="imagedata") {result_.content.minimumImages=1;}
            else if (name=="txBody") DrawingBody(e,{},wordTheme_,part);
            else WordWalk(e,table,part);
        }
    }
    void Word() {
        const auto styles=Related("word/document.xml","styles");
        if (!styles.empty()) {
            auto* root=Root(styles);defaults_=Child(Child(Child(root,"docDefaults"),"rPrDefault"),"rPr");
            for (auto* e=root->FirstChildElement();e;e=e->NextSiblingElement()) if (Local(e->Name())=="style") {
                const auto id=Attr(e,"styleId");if (!styles_.emplace(id,e).second) Unresolved();
                if (Attr(e,"default")=="1" || Attr(e,"default")=="true") {
                    if (Attr(e,"type")=="paragraph") defaultStyle_=id;
                    if (Attr(e,"type")=="character") defaultCharacter_=id;
                }
            }
        }
        const auto settings=Related("word/document.xml","settings");
        if (!settings.empty()) {evenHeaders_=On(Child(Root(settings),"evenAndOddHeaders"));themeLanguage_=Attr(Child(Root(settings),"themeFontLang"),"eastAsia");}
        wordTheme_=Related("word/document.xml","theme");WordWalk(Root("word/document.xml"),Spec{},"word/document.xml");
    }
    E* Placeholder(E* root,E* shape) {
        auto* ph=Desc(Child(shape,"nvSpPr"),"ph");if (!ph) return nullptr;
        E* result=nullptr;E* byType=nullptr;unsigned typeMatches=0;
        const auto id=Attr(ph,"idx").empty()?"0":Attr(ph,"idx");
        const auto search=[&](const auto& self,E* node)->void {
            if (!node) return;
            for (auto* e=node->FirstChildElement();e;e=e->NextSiblingElement()) {
                if (Local(e->Name())=="sp") {
                    auto* candidate=Desc(Child(e,"nvSpPr"),"ph");
                    if (candidate) {
                        const auto candidateId=Attr(candidate,"idx").empty()?"0":Attr(candidate,"idx");
                        if (candidateId==id) {if (result) Unresolved();result=e;}
                        if (!Attr(ph,"type").empty() && Attr(ph,"type")==Attr(candidate,"type")) {byType=e;++typeMatches;}
                    }
                } else self(self,e);
            }
        };search(search,root);return result?result:typeMatches==1?byType:nullptr;
    }
    E* Level(E* list,unsigned level) {
        const auto name="lvl"+std::to_string(level+1)+"pPr";return Child(list,name.c_str());
    }
    void DrawingBody(E* body,const std::vector<E*>& inherited,const std::string& theme,const std::string& part,const std::string& fontReference="minor") {
        for (auto* p=body->FirstChildElement();p;p=p->NextSiblingElement()) if (Local(p->Name())=="p") {
            const auto value=Attr(Child(p,"pPr"),"lvl");
            if (!value.empty() && (value.size()!=1 || value[0]<'0' || value[0]>'8')) Unresolved();
            const unsigned level=value.empty()?0:static_cast<unsigned>(value[0]-'0');
            Spec spec;
            if (!theme.empty() && fontReference!="none") {
                const std::string prefix=fontReference=="major"?"+mj-":"+mn-";
                spec.names={prefix+"lt",prefix+"lt",prefix+"ea",prefix+"cs"};spec.themed.fill(true);
            }
            std::vector<E*> properties;
            for (auto* list:inherited) {
                if (!list) continue;
                if (auto* d=Child(list,"defPPr")) properties.push_back(d);
                if (auto* l=Level(list,level)) properties.push_back(l);
                if (Local(list->Name())=="pPr") properties.push_back(list);
            }
            if (auto* list=Child(body,"lstStyle")) {
                if (auto* d=Child(list,"defPPr")) properties.push_back(d);
                if (auto* l=Level(list,level)) properties.push_back(l);
            }
            if (auto* own=Child(p,"pPr")) properties.push_back(own);
            E* bullet=nullptr;E* bulletFont=nullptr;
            for (auto* props:properties) {
                DrawingProps(Child(props,"defRPr"),spec);
                if (Child(props,"buNone")) bullet=nullptr;
                if (Child(props,"buChar")) bullet=Child(props,"buChar");
                if (Child(props,"buAutoNum")) bullet=Child(props,"buAutoNum");
                if (Child(props,"buFont")) bulletFont=Child(props,"buFont");
                if (Child(props,"buFontTx")) bulletFont=nullptr;
            }
            bool hasText=false;
            for (auto* run=p->FirstChildElement();run;run=run->NextSiblingElement()) {
                const auto kind=Local(run->Name());
                if (kind!="r" && kind!="fld") continue;
                auto* t=Child(run,"t");if (!t || !t->GetText()) continue;
                Spec text=spec;DrawingProps(Child(run,"rPr"),text);Add(t->GetText(),text,theme,part);hasText=true;
            }
            if (bullet && hasText) {
                Spec mark=spec;const auto family=Attr(bulletFont,"typeface");if (!family.empty()) {mark.names.fill(family);mark.themed.fill(family[0]=='+');}
                Add(Local(bullet->Name())=="buChar"?Attr(bullet,"char"):"0123456789.",mark,theme,part,false,false);
            }
        }
    }
    void SlideWalk(E* root,E* master,E* layout,E* presentation,const std::string& theme,const std::string& part) {
        for (auto* e=root->FirstChildElement();e;e=e->NextSiblingElement()) {
            const auto name=Local(e->Name());
            if (name=="sp") {
                auto* ph=Desc(Child(e,"nvSpPr"),"ph");
                auto* layoutShape=Placeholder(layout,e);auto* masterShape=Placeholder(master,layoutShape?layoutShape:e);
                auto type=Attr(ph,"type");
                if (type.empty()) type=Attr(Desc(Child(layoutShape,"nvSpPr"),"ph"),"type");
                if (type.empty()) type=Attr(Desc(Child(masterShape,"nvSpPr"),"ph"),"type");
                const char* style=type=="title" || type=="ctrTitle"?"titleStyle":ph?"bodyStyle":"otherStyle";
                std::vector<E*> inherited;
                if (auto* defaults=Child(presentation,"defaultTextStyle")) inherited.push_back(defaults);
                if (auto* textStyle=Child(Child(master,"txStyles"),style)) inherited.push_back(textStyle);
                for (auto* shape:{masterShape,layoutShape}) if (shape) {
                    auto* body=Child(shape,"txBody");if (auto* list=Child(body,"lstStyle")) inherited.push_back(list);
                    if (auto* first=Child(body,"p")) if (auto* props=Child(first,"pPr")) inherited.push_back(props);
                }
                auto* reference=Child(Child(e,"style"),"fontRef");
                const auto index=reference?Attr(reference,"idx"):"minor";
                if (index!="major" && index!="minor" && index!="none") Unresolved();
                if (auto* body=Child(e,"txBody")) DrawingBody(body,inherited,theme,part,index);
                if (Desc(e,"blip")) result_.content.minimumImages=1;
            } else if (name=="txBody") DrawingBody(e,{Child(presentation,"defaultTextStyle")},theme,part);
            else if (name=="blip") result_.content.minimumImages=1;
            else SlideWalk(e,master,layout,presentation,theme,part);
        }
    }
    void Slides() {
        auto* presentation=Root("ppt/presentation.xml");auto* list=Child(presentation,"sldIdLst");std::vector<std::string> slides;
        if (list) for (auto* e=list->FirstChildElement();e;e=e->NextSiblingElement()) {
            // p:sldId has both an unqualified numeric id and an r:id.
            std::string id;
            for (auto* a=e->FirstAttribute();a;a=a->Next()) if (std::strchr(a->Name(),':') && Local(a->Name())=="id") id=a->Value();
            if (id.empty()) Unresolved();slides.push_back(Related("ppt/presentation.xml","slide",id));
        }
        else for (const auto& entry:parts_) if (entry.first.rfind("ppt/slides/slide",0)==0 && entry.first.size()>4 && entry.first.substr(entry.first.size()-4)==".xml") slides.push_back(entry.first);
        std::set<std::string> seen;result_.slides=static_cast<std::uint32_t>(slides.size());
        if (slides.empty()) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_FORMAT_MISMATCH");
        for (const auto& part:slides) {
            if (!seen.insert(part).second) Unresolved();
            const auto layout=Related(part,"slideLayout"),master=layout.empty()?std::string{}:Related(layout,"slideMaster");
            auto theme=Related(part,"theme");if (theme.empty() && !master.empty()) theme=Related(master,"theme");
            if (!layout.empty() && !Related(layout,"themeOverride").empty()) Unresolved();
            SlideWalk(Root(part),Root(master),Root(layout),presentation,theme,part);
            // Non-placeholder shapes on master/layout are rendered on every slide too.
            for (const auto& inherited:{master,layout}) if (!inherited.empty()) {
                if (inherited==master && (Attr(Root(part),"showMasterSp")=="0" || Attr(Root(part),"showMasterSp")=="false" ||
                    Attr(Root(layout),"showMasterSp")=="0" || Attr(Root(layout),"showMasterSp")=="false")) continue;
                const auto walk=[&](const auto& self,E* parent)->void {
                    if (!parent) return;
                    for (auto* e=parent->FirstChildElement();e;e=e->NextSiblingElement()) {
                        if (Local(e->Name())=="sp" && !Desc(Child(e,"nvSpPr"),"ph")) {
                            if (auto* body=Child(e,"txBody")) DrawingBody(body,{Child(Child(Root(master),"txStyles"),"otherStyle")},theme,inherited);
                        } else if (Local(e->Name())!="sp") self(self,e);
                    }
                };walk(walk,Root(inherited));
            }
        }
        result_.content.pageCount=result_.slides;
    }
    void Finish() {
        std::set<std::string> names;
        for (auto& entry:uses_) {
            auto& use=entry.second;std::sort(use.characters.begin(),use.characters.end());
            use.characters.erase(std::unique(use.characters.begin(),use.characters.end()),use.characters.end());
            if (!use.family.empty()) names.insert(use.family);result_.fontUses.push_back(std::move(use));
        }
        if (names.size()>1024) throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_FONT_LIMIT");
        result_.fonts.assign(names.begin(),names.end());result_.content.textMinimum.assign(text_.begin(),text_.end());
    }
};
}
void ResolveOfficeFontUsage(const std::map<std::string,std::string>& parts,const std::string& format,OfficeInput& result) {
    Usage usage(parts,result);if (format=="docx") usage.Word();else usage.Slides();usage.Finish();
}
Status ValidateOfficeFontUsage(const std::vector<OfficeFontUse>& uses,
    const std::function<bool(const std::string&)>& familyAvailable,
    const std::function<bool(const std::string&,std::uint32_t)>& hasGlyph,
    bool approved,std::vector<FontDiagnostic>& diagnostics) {
    bool missing=false,glyph=false,symbol=false;diagnostics.clear();
    for (const auto& use:uses) {
        const bool absent=!use.family.empty() && !familyAvailable(use.family);bool badGlyph=false;
        for (const auto cp:use.characters) {
            const bool icon=use.symbol || Private(cp);
            const bool covered=hasGlyph(icon?use.family:std::string{},cp) && (!icon || (!use.family.empty() && !absent));
            if (!covered) {badGlyph=true;if (icon) symbol=true;else glyph=true;}
        }
        if (absent || badGlyph) diagnostics.push_back({use.family,use.part});missing|=absent;
    }
    Status status;status.module="office";
    if (symbol || glyph || (missing && !approved)) {
        status.code=ErrorCode::FontMissing;status.reason=symbol?"OFFICE_SYMBOL_FONT_MISSING":glyph?"OFFICE_GLYPH_MISSING":"OFFICE_REQUIRED_FONT_MISSING";
        status.messageKey="errors.FONT_MISSING";
    }
    return status;
}
}
