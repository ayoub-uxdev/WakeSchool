#include "PronoteZlib.h"

#include <zlib.h>

int pronote_deflate_raw(
    const uint8_t *input,
    int input_length,
    uint8_t *output,
    int *output_length
) {
    z_stream stream = {0};
    int status = deflateInit2(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        -MAX_WBITS,
        8,
        Z_DEFAULT_STRATEGY
    );
    if (status != Z_OK) {
        return -1;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = output;
    stream.avail_out = (uInt)*output_length;
    status = deflate(&stream, Z_FINISH);
    *output_length = (int)stream.total_out;
    deflateEnd(&stream);

    if (status == Z_STREAM_END) {
        return 1;
    }
    return status == Z_BUF_ERROR ? 0 : -1;
}

int pronote_inflate_raw(
    const uint8_t *input,
    int input_length,
    uint8_t *output,
    int *output_length
) {
    z_stream stream = {0};
    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) {
        return -1;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = output;
    stream.avail_out = (uInt)*output_length;
    status = inflate(&stream, Z_FINISH);
    *output_length = (int)stream.total_out;
    inflateEnd(&stream);

    if (status == Z_STREAM_END) {
        return 1;
    }
    return status == Z_BUF_ERROR ? 0 : -1;
}
