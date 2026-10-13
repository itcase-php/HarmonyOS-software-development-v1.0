#include "office_input.h"
#include "../napi/bridge_problem.h"
#include <miniz.h>
#include <tinyxml2.h>
#include <algorithm>
#include <fstream>
#include <set>
#include <cstring>
#include <map>
#include "office_media.h"

namespace hdm::production {
namespace {
std::string Local(const char* name) {
    if (!name) return {}; const std::string text=name;
    const auto colon=text.find(':'); return text.substr(colon==std::string::npos?0:colon+1);
}
bool Namespace(tinyxml2::XMLElement* root,const char* expected,const char* strict=nullptr) {
    const std::string name=root->Name(); const auto colon=name.find(':');
    const std::string key=colon==std::string::npos?"xmlns":"xmlns:"+name.substr(0,colon);
    const auto* value=root->Attribute(key.c_str());
    return value && (std::strcmp(value,expected)==0 || (strict && std::strcmp(value,strict)==0));
}
void Xml(tinyxml2::XMLNode* node,std::set<std::string>& fonts,std::size_t depth=0) {
    if (depth>128) throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_XML_DEPTH");
    for (;node;node=node->NextSibling()) {
        if (node->ToUnknown()) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_OFFICE_XML_DECLARATION");
        if (auto* element=node->ToElement()) {
            const auto name=Local(element->Name());
            if (name=="documentProtection" || name=="writeProtection" || name=="modifyVerifier" || name=="cryptProvider")
                throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_OFFICE_PROTECTED");
            if (name=="Relationship") {
                const auto* mode=element->Attribute("TargetMode");
                const auto* target=element->Attribute("Target");
                if ((mode && std::strcmp(mode,"Internal")) || !target || std::strstr(target,":") || target[0]=='/' ||
                    std::strstr(target,"../../") || std::strchr(target,'\\'))
                    throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_OFFICE_EXTERNAL_RELATIONSHIP");
            }
            for (const auto* attribute=element->FirstAttribute();attribute;attribute=attribute->Next()) {
                const auto key=Local(attribute->Name()); const std::string value=attribute->Value();
                if ((key=="Type" || key=="ContentType") && value.find("digital-signature")!=std::string::npos)
                    throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_OFFICE_SIGNED");
                if (key=="ContentType" && (value.find("macroEnabled")!=std::string::npos || value.find("vbaProject")!=std::string::npos))
                    throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_OFFICE_ACTIVE_CONTENT");
                if ((name=="rFonts" && (key=="ascii" || key=="hAnsi" || key=="eastAsia" || key=="cs")) ||
                    (name=="sym" && key=="font") || (key=="typeface" && name!="font")) {
                    if (value.size()>256 || fonts.size()>1024)
                        throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_FONT_LIMIT");
                    if (!value.empty() && value[0]!='+') fonts.insert(value);
                }
            }
        }
        Xml(node->FirstChild(),fonts,depth+1);
    }
}
struct Count { std::uint64_t bytes{},limit{}; };
void Content(tinyxml2::XMLNode* node,std::map<std::uint32_t,std::uint32_t>& text,
             bool& image,bool& privateGlyphs,std::uint64_t& characters) {
    for (;node;node=node->NextSibling()) {
        if (auto* element=node->ToElement()) {
            const auto name=Local(element->Name());
            if (name=="blip" || name=="imagedata") image=true;
            if (name=="sym") privateGlyphs=true;
            if (name=="t" && element->GetText()) {
                const auto* p=reinterpret_cast<const unsigned char*>(element->GetText());
                while (*p) {
                    std::uint32_t cp=*p++; int more=0;
                    if (cp>=0xc2 && cp<=0xdf) {cp&=31;more=1;}
                    else if (cp>=0xe0 && cp<=0xef) {cp&=15;more=2;}
                    else if (cp>=0xf0 && cp<=0xf4) {cp&=7;more=3;}
                    else if (cp>=0x80) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
                    for(int index=0;index<more;++index) {
                        if ((*p&0xc0)!=0x80) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
                        cp=(cp<<6)|(*p++&63);
                    }
                    if ((more==1 && cp<128) || (more==2 && cp<2048) || (more==3 && cp<65536) ||
                        cp>0x10ffff || (cp>=0xd800 && cp<=0xdfff))
                        throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_TEXT_ENCODING");
                    if (cp<=32 || cp==0xa0 || cp==0xad || (cp>=0x2000 && cp<=0x200f) ||
                        (cp>=0x2028 && cp<=0x202f) || (cp>=0x2060 && cp<=0x206f) || cp==0xfeff) continue;
                    if (++characters>1000000 || text.size()>8192)
                        throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_TEXT_LIMIT");
                    ++text[cp];
                    privateGlyphs|=(cp>=0xe000 && cp<=0xf8ff) || (cp>=0xf0000 && cp<=0x10fffd);
                }
            }
        }
        Content(node->FirstChild(),text,image,privateGlyphs,characters);
    }
}
size_t CountBytes(void* opaque,mz_uint64 offset,const void*,size_t count) {
    auto& state=*static_cast<Count*>(opaque);
    if (offset!=state.bytes || count>state.limit-state.bytes) return 0;
    state.bytes+=count; return count;
}
}
OfficeInput InspectOffice(const std::filesystem::path& path,const std::string& format,const ResourceBudget& budget) {
    if (format!="docx" && format!="pptx") throw BridgeProblem(ErrorCode::UnsupportedFormat,"NATIVE_OFFICE_FORMAT");
    unsigned char signature[8]{}; std::ifstream input(path,std::ios::binary); input.read(reinterpret_cast<char*>(signature),8);
    const unsigned char ole[]={0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1};
    if (!std::memcmp(signature,ole,8)) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_OFFICE_ENCRYPTED_OR_LEGACY");
    if (signature[0]!='P' || signature[1]!='K') throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_SIGNATURE");
    mz_zip_archive archive{};
    if (!mz_zip_reader_init_file(&archive,path.string().c_str(),0))
        throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_ZIP");
    struct Cleanup { mz_zip_archive* zip; ~Cleanup(){ mz_zip_reader_end(zip); } } cleanup{&archive};
    const auto entries=mz_zip_reader_get_num_files(&archive);
    if (!entries || entries>4096) throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_ENTRY_LIMIT");
    std::set<std::string> names,fonts; std::uint64_t expanded{}; bool contentTypes=false,main=false,other=false,mainType=false;
    OfficeInput result;
    std::map<std::uint32_t,std::uint32_t> text;
    std::uint64_t characters{}; bool imageReference=false,hasBitmap=false;
    for (mz_uint index=0;index<entries;++index) {
        mz_zip_archive_file_stat info{};
        if (!mz_zip_reader_file_stat(&archive,index,&info)) throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_ZIP_ENTRY");
        const std::string name=info.m_filename;
        if (name.empty() || name.size()>400 || name[0]=='/' || name.find('\\')!=std::string::npos || name.find(':')!=std::string::npos ||
            name.find("../")!=std::string::npos || name==".." || name.find('%')!=std::string::npos || !names.insert(name).second)
            throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_ENTRY_NAME");
        if (info.m_is_encrypted) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_OFFICE_ENCRYPTED");
        if (name.rfind("_xmlsignatures/",0)==0) throw BridgeProblem(ErrorCode::PermissionDenied,"NATIVE_OFFICE_SIGNED");
        if (!info.m_is_supported || name.find("vbaProject")!=std::string::npos || name.find("activeX/")!=std::string::npos ||
            name.find("embeddings/")!=std::string::npos || name.find(".svg")!=std::string::npos)
            throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_OFFICE_ACTIVE_CONTENT");
        if (info.m_uncomp_size>16ULL*1024*1024 || info.m_uncomp_size>budget.maxTempBytes ||
            expanded>std::min<std::uint64_t>(budget.maxTempBytes,128ULL*1024*1024)-info.m_uncomp_size)
            throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_EXPANSION_LIMIT");
        expanded+=info.m_uncomp_size;
        if (info.m_is_directory) continue;
        contentTypes|=name=="[Content_Types].xml";
        main|=name==(format=="docx"?"word/document.xml":"ppt/presentation.xml");
        other|=name==(format=="docx"?"ppt/presentation.xml":"word/document.xml");
        if (name.rfind("ppt/slides/slide",0)==0 && name.size()>4 && name.substr(name.size()-4)==".xml") ++result.slides;
        const bool xml=name.size()>4 && (name.substr(name.size()-4)==".xml" || (name.size()>5 && name.substr(name.size()-5)==".rels"));
        if (xml) {
            if (info.m_uncomp_size>4ULL*1024*1024 || info.m_uncomp_size*24+8*1024*1024>budget.maxNativeBytes)
                throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_XML_LIMIT");
            std::string bytes(static_cast<std::size_t>(info.m_uncomp_size),'\0');
            if (!mz_zip_reader_extract_to_mem(&archive,index,bytes.data(),bytes.size(),0))
                throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_CRC");
            tinyxml2::XMLDocument document;
            if (document.Parse(bytes.data(),bytes.size())!=tinyxml2::XML_SUCCESS || !document.RootElement())
                throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_XML");
            if ((name=="word/document.xml" && Local(document.RootElement()->Name())!="document") ||
                (name=="ppt/presentation.xml" && Local(document.RootElement()->Name())!="presentation") ||
                (name=="[Content_Types].xml" && Local(document.RootElement()->Name())!="Types"))
                throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_MAIN_PART");
            if ((name=="word/document.xml" && !Namespace(document.RootElement(),
                    "http://schemas.openxmlformats.org/wordprocessingml/2006/main","http://purl.oclc.org/ooxml/wordprocessingml/main")) ||
                (name=="ppt/presentation.xml" && !Namespace(document.RootElement(),
                    "http://schemas.openxmlformats.org/presentationml/2006/main","http://purl.oclc.org/ooxml/presentationml/main")))
                throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_NAMESPACE");
            if (name=="[Content_Types].xml") {
                if (!Namespace(document.RootElement(),"http://schemas.openxmlformats.org/package/2006/content-types"))
                    throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_NAMESPACE");
                for (auto* child=document.RootElement()->FirstChildElement();child;child=child->NextSiblingElement()) {
                    const auto* part=child->Attribute("PartName"); const auto* type=child->Attribute("ContentType");
                    const std::string expectedPart=format=="docx"?"/word/document.xml":"/ppt/presentation.xml";
                    const std::string expectedType=format=="docx"?
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml":
                        "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml";
                    if (Local(child->Name())=="Override" && part && type && part==expectedPart && type==expectedType) mainType=true;
                }
            }
            Xml(document.FirstChild(),fonts);
            if (name=="word/document.xml" ||
                (name.rfind("ppt/slides/slide",0)==0 && name.substr(name.size()-4)==".xml")) {
                Content(document.FirstChild(),text,imageReference,result.hasPrivateGlyphs,characters);
            }
        } else {
            if (name.rfind("word/media/",0)==0 || name.rfind("ppt/media/",0)==0) {
                std::string media(static_cast<std::size_t>(info.m_uncomp_size),'\0');
                if (!mz_zip_reader_extract_to_mem(&archive,index,media.data(),media.size(),0))
                    throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_CRC");
                ValidateOfficeMedia(media,name,budget); hasBitmap=true;
                continue;
            }
            Count count{0,info.m_uncomp_size};
            if (!mz_zip_reader_extract_to_callback(&archive,index,CountBytes,&count,0) || count.bytes!=info.m_uncomp_size)
                throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_CRC");
        }
    }
    if (!contentTypes || !mainType || !main || other || (format=="pptx" && !result.slides))
        throw BridgeProblem(ErrorCode::FileCorrupted,"NATIVE_OFFICE_FORMAT_MISMATCH");
    if (result.slides>budget.maxPages) throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_PAGE_LIMIT");
    result.content.textMinimum.assign(text.begin(),text.end());
    result.content.minimumImages=imageReference && hasBitmap?1:0;
    if (format=="pptx") result.content.pageCount=result.slides;
    result.fonts.assign(fonts.begin(),fonts.end()); return result;
}
}
