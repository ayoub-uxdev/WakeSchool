#ifndef PRONOTE_ZLIB_H
#define PRONOTE_ZLIB_H

#include <stdint.h>

int pronote_deflate_raw(
    const uint8_t *input,
    int input_length,
    uint8_t *output,
    int *output_length
);

int pronote_inflate_raw(
    const uint8_t *input,
    int input_length,
    uint8_t *output,
    int *output_length
);

#endif
