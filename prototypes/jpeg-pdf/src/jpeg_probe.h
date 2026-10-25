#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef int (*HdmRead)(void*, unsigned char*, size_t, size_t*);
typedef int (*HdmCheck)(void*);
enum { HDM_JPEG_NONE, HDM_JPEG_METADATA, HDM_JPEG_ENCODING, HDM_JPEG_COLOR,
    HDM_JPEG_DENSITY, HDM_JPEG_HEADER, HDM_JPEG_PIXELS };
typedef struct {
    uint32_t width, height, components, density_unit, density_x, density_y;
    uint64_t peak;
    int issue;
    uint32_t orientation, icc_size;
    double exif_dpi_x, exif_dpi_y;
    unsigned char icc_profile[65536];
} HdmJpegInfo;
/* All longjmp state and allocations live in C, never across C++ destructors. */
int hdm_probe_jpeg(HdmRead, HdmCheck, void*, uint64_t memory_limit, uint64_t pixels_limit, HdmJpegInfo*);
#ifdef __cplusplus
}
#endif
