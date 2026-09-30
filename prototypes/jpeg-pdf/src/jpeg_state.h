#pragma once
#include <stdio.h>
#include <setjmp.h>
#include <jpeglib.h>
typedef struct {
    struct jpeg_error_mgr base;
    jmp_buf jump;
    size_t limit, live, peak;
    int code;
} HdmJpegError;
/* Referenced by the probe so the archive pulls our allocator object before the
 * upstream default jmemnobs object. Allocation counters are per decoder. */
void hdm_allocator_link_anchor(void);
