#include "jpeg_probe.h"
#include "jpeg_state.h"
#include "jpeg_metadata.h"
#include <jerror.h>
#include <stdlib.h>
#include <string.h>
enum { HDM_CORRUPT = 5, HDM_LIMIT = 6, HDM_UNSUPPORTED = 17 };
typedef struct {
    struct jpeg_decompress_struct jpeg;
    HdmJpegError error;
    struct jpeg_source_mgr source;
    HdmRead read;
    HdmCheck check;
    void* opaque;
    HdmJpegInfo* info;
    int header_checked;
    unsigned char buffer[65536];
} ProbeState;
static void fail(j_common_ptr jpeg) { longjmp(((HdmJpegError*)jpeg->err)->jump, 1); }
static void message(j_common_ptr jpeg, int level) { if (level < 0) fail(jpeg); }
static void init(j_decompress_ptr jpeg) { (void)jpeg; }
static void term(j_decompress_ptr jpeg) { (void)jpeg; }
/* The decompressor reports progressive/arith/precision, but its public v8
 * is_baseline field is not populated on decode. Confirm actual SOF0 directly
 * within a bounded first header chunk before passing bytes to libjpeg. */
static int baseline_header(const unsigned char* b, size_t n, HdmJpegInfo* info) {
    size_t p = 2;
    if (n < 4 || b[0] != 0xff || b[1] != 0xd8) return HDM_CORRUPT;
    while (p + 3 < n) {
        unsigned int marker, length;
        if (b[p++] != 0xff) return HDM_CORRUPT;
        while (p < n && b[p] == 0xff) ++p;
        if (p + 1 >= n) { info->issue = HDM_JPEG_HEADER; return HDM_UNSUPPORTED; }
        marker = b[p++];
        if (marker == 0xc0) return 0;
        if (marker == 0xda || marker == 0xd9 || marker == 0xd8) return HDM_CORRUPT;
        if (marker >= 0xe3 && marker <= 0xef) { info->issue = HDM_JPEG_METADATA; return HDM_UNSUPPORTED; }
        if ((marker >= 0xc1 && marker <= 0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc)) {
            info->issue = HDM_JPEG_ENCODING; return HDM_UNSUPPORTED;
        }
        length = ((unsigned int)b[p] << 8) | b[p+1];
        if (length < 2) return HDM_CORRUPT;
        if (length > n - p) { info->issue = HDM_JPEG_HEADER; return HDM_UNSUPPORTED; }
        p += length;
    }
    info->issue = HDM_JPEG_HEADER; return HDM_UNSUPPORTED;
}
static boolean fill(j_decompress_ptr jpeg) {
    ProbeState* state = (ProbeState*)jpeg->client_data;
    size_t count = 0;
    int code = state->read(state->opaque, state->buffer, sizeof(state->buffer), &count);
    if (code || !count || count > sizeof(state->buffer)) { state->error.code = code ? code : HDM_CORRUPT; fail((j_common_ptr)jpeg); }
    if (!state->header_checked) {
        state->error.code = baseline_header(state->buffer,count,state->info);
        if (state->error.code) fail((j_common_ptr)jpeg);
        state->header_checked = 1;
        state->error.code = HDM_CORRUPT;
    }
    state->source.next_input_byte = state->buffer; state->source.bytes_in_buffer = count;
    return TRUE;
}
static void skip(j_decompress_ptr jpeg, long count) {
    if (count <= 0) return;
    while ((size_t)count > jpeg->src->bytes_in_buffer) { count -= (long)jpeg->src->bytes_in_buffer; fill(jpeg); }
    jpeg->src->next_input_byte += count; jpeg->src->bytes_in_buffer -= (size_t)count;
}
static boolean reject_marker(j_decompress_ptr jpeg) {
    ((ProbeState*)jpeg->client_data)->info->issue = HDM_JPEG_METADATA;
    ((HdmJpegError*)jpeg->err)->code = HDM_UNSUPPORTED; fail((j_common_ptr)jpeg); return FALSE;
}
int hdm_probe_jpeg(HdmRead read, HdmCheck check, void* opaque, uint64_t memory_limit, uint64_t pixels_limit, HdmJpegInfo* info) {
    ProbeState* state;
    JSAMPARRAY row;
    int result = 0;
    info->issue = HDM_JPEG_NONE;
    info->orientation = 1; info->icc_size = 0; info->exif_dpi_x = info->exif_dpi_y = 0;
    if (memory_limit < sizeof(ProbeState)+sizeof(HdmJpegInfo) || memory_limit > SIZE_MAX) return HDM_LIMIT;
    state = (ProbeState*)calloc(1, sizeof(ProbeState));
    if (!state) return HDM_LIMIT;
    state->read = read; state->check = check; state->opaque = opaque; state->info = info;
    state->jpeg.err = jpeg_std_error(&state->error.base);
    state->error.base.error_exit = fail; state->error.base.emit_message = message;
    state->error.limit = (size_t)memory_limit; state->error.live = state->error.peak = sizeof(ProbeState)+sizeof(HdmJpegInfo);
    state->error.code = HDM_CORRUPT;
    hdm_allocator_link_anchor();
    if (setjmp(state->error.jump)) { result = state->error.code; goto cleanup; }
    jpeg_create_decompress(&state->jpeg); state->jpeg.client_data = state;
    state->source.init_source = init; state->source.fill_input_buffer = fill;
    state->source.skip_input_data = skip; state->source.resync_to_restart = jpeg_resync_to_restart;
    state->source.term_source = term; state->jpeg.src = &state->source;
    /* Save bounded EXIF/ICC headers with the budgeted libjpeg allocator.
     * Unknown APP segments remain unsupported; JPEG bytes stay unchanged. */
    jpeg_save_markers(&state->jpeg, JPEG_APP0+1, 65535);
    jpeg_save_markers(&state->jpeg, JPEG_APP0+2, 65535);
    { int marker; for (marker = 3; marker <= 15; ++marker)
        jpeg_set_marker_processor(&state->jpeg, JPEG_APP0 + marker, reject_marker); }
    if (jpeg_read_header(&state->jpeg, TRUE) != JPEG_HEADER_OK) fail((j_common_ptr)&state->jpeg);
    if (state->jpeg.progressive_mode || state->jpeg.arith_code || state->jpeg.data_precision != 8) {
        info->issue = HDM_JPEG_ENCODING;
        state->error.code = HDM_UNSUPPORTED; fail((j_common_ptr)&state->jpeg);
    }
    if (state->jpeg.jpeg_color_space != JCS_GRAYSCALE && state->jpeg.jpeg_color_space != JCS_YCbCr && state->jpeg.jpeg_color_space != JCS_RGB) {
        info->issue = HDM_JPEG_COLOR;
        state->error.code = HDM_UNSUPPORTED; fail((j_common_ptr)&state->jpeg);
    }
    if (!state->jpeg.image_width || !state->jpeg.image_height || (uint64_t)state->jpeg.image_width * state->jpeg.image_height > pixels_limit) {
        info->issue = HDM_JPEG_PIXELS;
        state->error.code = HDM_LIMIT; fail((j_common_ptr)&state->jpeg);
    }
    info->width = state->jpeg.image_width; info->height = state->jpeg.image_height;
    info->components = state->jpeg.num_components;
    state->error.code = hdm_jpeg_metadata(&state->jpeg,info);
    if (state->error.code) fail((j_common_ptr)&state->jpeg);
    state->error.code = HDM_CORRUPT;
    /* Do not accept metadata appearing after the image header was checked. */
    jpeg_set_marker_processor(&state->jpeg, JPEG_APP0+1, reject_marker);
    jpeg_set_marker_processor(&state->jpeg, JPEG_APP0+2, reject_marker);
    if (state->jpeg.saw_JFIF_marker) {
        info->density_unit = state->jpeg.density_unit; info->density_x = state->jpeg.X_density; info->density_y = state->jpeg.Y_density;
        if (info->density_unit > 2 || !info->density_x || !info->density_y || (!info->density_unit && info->density_x != info->density_y)) {
            info->issue = HDM_JPEG_DENSITY;
            state->error.code = HDM_UNSUPPORTED; fail((j_common_ptr)&state->jpeg);
        }
    }
    state->jpeg.out_color_space = info->components == 1 ? JCS_GRAYSCALE : JCS_RGB;
    if (!jpeg_start_decompress(&state->jpeg)) fail((j_common_ptr)&state->jpeg);
    row = (*state->jpeg.mem->alloc_sarray)((j_common_ptr)&state->jpeg, JPOOL_IMAGE,
        state->jpeg.output_width * state->jpeg.output_components, 1);
    while (state->jpeg.output_scanline < state->jpeg.output_height) {
        state->error.code = check(opaque);
        if (state->error.code) fail((j_common_ptr)&state->jpeg);
        state->error.code = HDM_CORRUPT;
        if (jpeg_read_scanlines(&state->jpeg, row, 1) != 1) fail((j_common_ptr)&state->jpeg);
    }
    if (!jpeg_finish_decompress(&state->jpeg)) fail((j_common_ptr)&state->jpeg);
    /* No synthesized EOI, ignored warnings, or accepted trailing payload. */
    if (state->source.bytes_in_buffer) fail((j_common_ptr)&state->jpeg);
    { size_t count = 0; int code = read(opaque, state->buffer, 1, &count);
      if (code || count) { state->error.code = code ? code : HDM_CORRUPT; fail((j_common_ptr)&state->jpeg); } }
cleanup:
    info->peak = state->error.peak;
    if (state->jpeg.mem) jpeg_destroy_decompress(&state->jpeg);
    free(state); return result;
}
