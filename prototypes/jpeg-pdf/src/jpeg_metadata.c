#include "jpeg_metadata.h"
#include <stdio.h>
#include <jpeglib.h>
#include <string.h>
enum { CORRUPT = 5, UNSUPPORTED = 17 };
static uint32_t u16(const unsigned char* p, int little) {
    return little ? (uint32_t)p[0] | ((uint32_t)p[1] << 8) : ((uint32_t)p[0] << 8) | p[1];
}
static uint32_t u32(const unsigned char* p, int little) {
    return little ? u16(p,1) | (u16(p+2,1) << 16) : (u16(p,0) << 16) | u16(p+2,0);
}
static int exif_color(const unsigned char* p, size_t n, uint32_t offset, int little, int* uncalibrated) {
    uint32_t count, i, seen = 0;
    if (offset < 8 || offset > n || n-offset < 2) return CORRUPT;
    count = u16(p+offset,little); offset += 2;
    if (n-offset < 4 || count > (n-offset-4)/12) return CORRUPT;
    for (i = 0; i < count; ++i) {
        const unsigned char* entry = p+offset+i*12;
        if (u16(entry,little) != 0xa001) continue;
        if (seen++ || u16(entry+2,little) != 3 || u32(entry+4,little) != 1) return CORRUPT;
        *uncalibrated = u16(entry+8,little) != 1;
    }
    return 0;
}
static int exif(const unsigned char* p, size_t n, HdmJpegInfo* info, int* uncalibrated) {
    uint32_t offset, count, i, seen = 0, unit = 2, color_ifd = 0;
    double x = 0, y = 0;
    int little;
    if (n < 6 || memcmp(p,"Exif\0\0",6)) return UNSUPPORTED;
    if (n < 14) return CORRUPT;
    p += 6; n -= 6;
    if (!memcmp(p,"II",2)) little = 1;
    else if (!memcmp(p,"MM",2)) little = 0;
    else return CORRUPT;
    if (u16(p+2,little) != 42) return CORRUPT;
    offset = u32(p+4,little);
    if (offset < 8 || offset > n || n-offset < 2) return CORRUPT;
    count = u16(p+offset,little); offset += 2;
    if (n-offset < 4 || count > (n-offset-4)/12) return CORRUPT;
    for (i = 0; i < count; ++i) {
        const unsigned char* entry = p+offset+i*12;
        uint32_t tag = u16(entry,little), bit = 0;
        if (tag == 0x112) bit = 1;
        if (tag == 0x11a) bit = 2;
        if (tag == 0x11b) bit = 4;
        if (tag == 0x128) bit = 8;
        if (tag == 0x8769) bit = 16;
        if (!bit) continue;
        if (seen & bit) return CORRUPT;
        seen |= bit;
        if (u32(entry+4,little) != 1) return CORRUPT;
        if (bit == 16) {
            if (u16(entry+2,little) != 4) return CORRUPT;
            color_ifd = u32(entry+8,little);
            if (!color_ifd) return CORRUPT;
        } else if (bit == 1 || bit == 8) {
            uint32_t value = u16(entry+8,little);
            if (u16(entry+2,little) != 3) return CORRUPT;
            if (bit == 1) {
                if (value < 1 || value > 8) return CORRUPT;
                info->orientation = value;
            } else { if (value < 1 || value > 3) return CORRUPT; unit = value; }
        } else {
            uint32_t at = u32(entry+8,little), denominator;
            if (u16(entry+2,little) != 5 || at > n || n-at < 8) return CORRUPT;
            denominator = u32(p+at+4,little);
            if (!denominator || !u32(p+at,little)) return CORRUPT;
            if (bit == 2) x = (double)u32(p+at,little)/denominator;
            else y = (double)u32(p+at,little)/denominator;
        }
    }
    if (color_ifd) { int code = exif_color(p,n,color_ifd,little,uncalibrated); if (code) return code; }
    if ((x == 0) != (y == 0) || (unit == 1 && x != y)) {
        info->issue = HDM_JPEG_DENSITY; return UNSUPPORTED;
    }
    if (unit != 1) { info->exif_dpi_x = x*(unit == 3 ? 2.54 : 1); info->exif_dpi_y = y*(unit == 3 ? 2.54 : 1); }
    return 0;
}
static int profile(HdmJpegInfo* info) {
    const unsigned char* p = info->icc_profile;
    uint32_t n = info->icc_size, count, i;
    if (n < 132 || u32(p,0) != n || memcmp(p+36,"acsp",4)) return CORRUPT;
    if ((p[8] != 2 && p[8] != 4) ||
        (memcmp(p+12,"mntr",4) && memcmp(p+12,"scnr",4) && memcmp(p+12,"prtr",4) && memcmp(p+12,"spac",4)) ||
        (memcmp(p+20,"XYZ ",4) && memcmp(p+20,"Lab ",4))) return UNSUPPORTED;
    if (memcmp(p+16,info->components == 1 ? "GRAY" : "RGB ",4)) {
        info->issue = HDM_JPEG_COLOR; return UNSUPPORTED;
    }
    if (u32(p+64,0) > 3) return CORRUPT;
    count = u32(p+128,0);
    if (!count || count > (n-132)/12) return CORRUPT;
    for (i = 0; i < count; ++i) {
        uint32_t at = u32(p+132+i*12+4,0), length = u32(p+132+i*12+8,0);
        if (at < 132+count*12 || at%4 || at > n || length < 8 || length > n-at) return CORRUPT;
    }
    return 0;
}
int hdm_jpeg_metadata(struct jpeg_decompress_struct* jpeg, HdmJpegInfo* info) {
    jpeg_saved_marker_ptr marker, chunks[256] = {0};
    unsigned int total = 0, found = 0, has_exif = 0, i;
    int uncalibrated = 0;
    info->issue = HDM_JPEG_METADATA;
    for (marker = jpeg->marker_list; marker; marker = marker->next) {
        const unsigned char* p = marker->data;
        if (marker->data_length != marker->original_length) return CORRUPT;
        if (marker->marker == JPEG_APP0+1) {
            int code;
            if (has_exif++) return CORRUPT;
            code = exif(p,marker->data_length,info,&uncalibrated);
            if (code) return code;
        } else if (marker->marker == JPEG_APP0+2) {
            unsigned int sequence, count;
            if (marker->data_length < 14 || memcmp(p,"ICC_PROFILE\0",12)) return UNSUPPORTED;
            sequence = p[12]; count = p[13];
            if (!count || !sequence || sequence > count || chunks[sequence] || (total && total != count)) return CORRUPT;
            total = count; chunks[sequence] = marker; ++found;
        }
    }
    if (found != total) return CORRUPT;
    for (i = 1; i <= total; ++i) {
        size_t bytes = chunks[i]->data_length-14;
        if (bytes > sizeof(info->icc_profile)-info->icc_size) return UNSUPPORTED;
        memcpy(info->icc_profile+info->icc_size,chunks[i]->data+14,bytes);
        info->icc_size += (uint32_t)bytes;
    }
    if (info->icc_size) { int code = profile(info); if (code) return code; }
    else if (total) return CORRUPT;
    if (uncalibrated && !info->icc_size) { info->issue = HDM_JPEG_COLOR; return UNSUPPORTED; }
    info->issue = HDM_JPEG_NONE;
    return 0;
}
