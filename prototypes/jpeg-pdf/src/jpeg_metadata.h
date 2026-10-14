#pragma once
#include "jpeg_probe.h"
struct jpeg_decompress_struct;
int hdm_jpeg_metadata(struct jpeg_decompress_struct*, HdmJpegInfo*);
