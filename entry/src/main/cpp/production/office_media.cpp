#include "office_media.h"
#include "../napi/bridge_problem.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <csetjmp>
#include <jpeglib.h>
#include <jerror.h>
#include <png.h>
#include <vector>
extern "C" {
#include "jpeg_state.h"
}
namespace hdm::production {
namespace {
// The shared codec uses the prototype's budgeted system allocator. Its error
// prefix is part of that allocator contract, not just jpeg_error_mgr.
struct JpegError { HdmJpegError tracked; int warnings{}; };
void Fail(j_common_ptr info) {
    auto* error=reinterpret_cast<JpegError*>(info->err);
    if (error->tracked.code!=static_cast<int>(ErrorCode::ResourceLimitExceeded)) error->tracked.code=static_cast<int>(ErrorCode::FileCorrupted);
    longjmp(error->tracked.jump,1);
}
void Message(j_common_ptr info,int level) {
    if (level<0) ++reinterpret_cast<JpegError*>(info->err)->warnings;
}
ErrorCode Jpeg(const std::string& data,const ResourceBudget& budget) {
    jpeg_decompress_struct decoder{}; JpegError error{};
    decoder.err=jpeg_std_error(&error.tracked.base);error.tracked.base.error_exit=Fail;error.tracked.base.emit_message=Message;
    error.tracked.limit=static_cast<std::size_t>(budget.maxNativeBytes>data.size()?budget.maxNativeBytes-data.size():0);
    error.tracked.code=static_cast<int>(ErrorCode::FileCorrupted);hdm_allocator_link_anchor();
    if (setjmp(error.tracked.jump)) { jpeg_destroy_decompress(&decoder);
        return static_cast<ErrorCode>(error.tracked.code); }
    jpeg_create_decompress(&decoder);
    jpeg_mem_src(&decoder,reinterpret_cast<const unsigned char*>(data.data()),static_cast<unsigned long>(data.size()));
    jpeg_read_header(&decoder,TRUE);
    const auto pixels=std::uint64_t(decoder.image_width)*decoder.image_height;
    if (!pixels || pixels>budget.maxPixels || pixels*8+data.size()>budget.maxNativeBytes) {
        jpeg_destroy_decompress(&decoder);return ErrorCode::ResourceLimitExceeded;
    }
    decoder.mem->max_memory_to_use=static_cast<long>(budget.maxNativeBytes/2);
    decoder.scale_num=1;decoder.scale_denom=8;
    jpeg_start_decompress(&decoder);
    const auto row=(*decoder.mem->alloc_sarray)(reinterpret_cast<j_common_ptr>(&decoder),JPOOL_IMAGE,
        decoder.output_width*decoder.output_components,1);
    while (decoder.output_scanline<decoder.output_height) jpeg_read_scanlines(&decoder,row,1);
    jpeg_finish_decompress(&decoder);jpeg_destroy_decompress(&decoder);
    return error.warnings?ErrorCode::FileCorrupted:ErrorCode::Ok;
}
}
void ValidateOfficeMedia(const std::string& data,const std::string& name,const ResourceBudget& budget) {
    ErrorCode code=ErrorCode::FileCorrupted;
    if (data.size()>=8 && png_sig_cmp(reinterpret_cast<const unsigned char*>(data.data()),0,8)==0) {
        png_image image{};image.version=PNG_IMAGE_VERSION;
        struct Cleanup {png_image* image;~Cleanup(){png_image_free(image);}} cleanup{&image};
        if (png_image_begin_read_from_memory(&image,data.data(),data.size())) {
            const auto pixels=std::uint64_t(image.width)*image.height;
            if (!pixels || pixels>budget.maxPixels || pixels*8+data.size()>budget.maxNativeBytes)
                throw BridgeProblem(ErrorCode::ResourceLimitExceeded,"NATIVE_OFFICE_IMAGE_LIMIT");
            image.format=PNG_FORMAT_RGBA;std::vector<unsigned char> rgba(static_cast<std::size_t>(pixels)*4);
            if (png_image_finish_read(&image,nullptr,rgba.data(),0,nullptr)) code=ErrorCode::Ok;
        }
    } else if (data.size()>=2 && static_cast<unsigned char>(data[0])==0xff && static_cast<unsigned char>(data[1])==0xd8) {
        code=Jpeg(data,budget);
    } else {
        const auto dot=name.find_last_of('.'); const auto extension=dot==std::string::npos?"":name.substr(dot);
        if (extension!=".png" && extension!=".jpg" && extension!=".jpeg")
            throw BridgeProblem(ErrorCode::UnsupportedFeature,"NATIVE_OFFICE_MEDIA_UNVERIFIED");
    }
    if (code!=ErrorCode::Ok) throw BridgeProblem(code,"NATIVE_OFFICE_IMAGE_INVALID");
}
}
