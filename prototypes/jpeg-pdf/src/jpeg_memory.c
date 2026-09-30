/* Independent host-prototype allocator for the pinned libjpeg system-memory
 * interface. No upstream implementation is copied or shipped in the app. */
#define JPEG_INTERNALS
#include "jpeg_state.h"
#include <jerror.h>
#include <jmemsys.h>
#include <stdlib.h>
void hdm_allocator_link_anchor(void) {}
GLOBAL(void*) jpeg_get_small(j_common_ptr cinfo, size_t size) {
    HdmJpegError* error = (HdmJpegError*)cinfo->err;
    void* memory;
    if (error->live > error->limit || size > error->limit - error->live) { error->code = 6; return NULL; }
    memory = malloc(size);
    if (!memory) { error->code = 6; return NULL; }
    error->live += size;
    if (error->live > error->peak) error->peak = error->live;
    return memory;
}
GLOBAL(void) jpeg_free_small(j_common_ptr cinfo, void* memory, size_t size) {
    HdmJpegError* error = (HdmJpegError*)cinfo->err;
    if (memory) { free(memory); error->live -= size; }
}
GLOBAL(void*) jpeg_get_large(j_common_ptr cinfo, size_t size) { return jpeg_get_small(cinfo, size); }
GLOBAL(void) jpeg_free_large(j_common_ptr cinfo, void* memory, size_t size) { jpeg_free_small(cinfo, memory, size); }
GLOBAL(size_t) jpeg_mem_available(j_common_ptr cinfo, size_t minimum, size_t maximum, size_t already) {
    HdmJpegError* error = (HdmJpegError*)cinfo->err;
    size_t remaining = error->limit - error->live;
    (void)minimum; (void)already;
    return maximum < remaining ? maximum : remaining;
}
GLOBAL(void) jpeg_open_backing_store(j_common_ptr cinfo, backing_store_ptr store, long bytes) {
    (void)store; (void)bytes; ((HdmJpegError*)cinfo->err)->code = 6;
    ERREXIT(cinfo, JERR_NO_BACKING_STORE);
}
GLOBAL(long) jpeg_mem_init(j_common_ptr cinfo) { (void)cinfo; return 0; }
GLOBAL(void) jpeg_mem_term(j_common_ptr cinfo) { (void)cinfo; }
