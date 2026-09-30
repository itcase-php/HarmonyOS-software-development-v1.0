#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef int (*HdmRead)(void*, unsigned char*, size_t, size_t*);
typedef int (*HdmCheck)(void*);
typedef struct {
    uint32_t width, height, components, density_unit, density_x, density_y;
    uint64_t peak;
} HdmJpegInfo;
/* All longjmp state and allocations live in C, never across C++ destructors. */
int hdm_probe_jpeg(HdmRead, HdmCheck, void*, uint64_t memory_limit, uint64_t pixels_limit, HdmJpegInfo*);
#ifdef __cplusplus
}
#endif
