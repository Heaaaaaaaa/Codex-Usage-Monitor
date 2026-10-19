#include "UsageLogReader.h"
#include "../ThirdParty/zstd/zstd.h"
#include <stdio.h>
#include <stdlib.h>

struct UsageLogDecoder {
    FILE *file;
    ZSTD_DStream *stream;
    ZSTD_inBuffer input;
    unsigned char buffer[65536];
    size_t remaining;
    int failed;
};

UsageLogDecoder *usage_log_open(const char *path) {
    UsageLogDecoder *decoder = calloc(1, sizeof(*decoder));
    if (!decoder) return NULL;
    decoder->file = fopen(path, "rb");
    decoder->stream = ZSTD_createDStream();
    if (!decoder->file || !decoder->stream) {
        usage_log_close(decoder);
        return NULL;
    }
    // Bound the decompressor's window independently of the JSONL line limit.
    if (ZSTD_isError(ZSTD_DCtx_setParameter(decoder->stream, ZSTD_d_windowLogMax, 27))) {
        usage_log_close(decoder);
        return NULL;
    }
    decoder->remaining = 1;
    decoder->input.src = decoder->buffer;
    return decoder;
}

int64_t usage_log_read(UsageLogDecoder *decoder, void *destination, size_t capacity) {
    if (!decoder || decoder->failed || !capacity) return -1;
    ZSTD_outBuffer output = {destination, capacity, 0};
    while (!output.pos) {
        if (decoder->input.pos == decoder->input.size) {
            decoder->input.size = fread(decoder->buffer, 1, sizeof(decoder->buffer), decoder->file);
            decoder->input.pos = 0;
            if (!decoder->input.size) {
                if (ferror(decoder->file)) {
                    decoder->failed = 1;
                    return -1;
                }
                if (decoder->remaining == 0) return 0;
            }
        }
        decoder->remaining = ZSTD_decompressStream(decoder->stream, &output, &decoder->input);
        if (ZSTD_isError(decoder->remaining)) {
            decoder->failed = 1;
            return -1;
        }
        if (!output.pos && !decoder->input.size) {
            if (decoder->remaining == 0) return 0;
            decoder->failed = 1;
            return -1;
        }
    }
    return (int64_t)output.pos;
}

void usage_log_close(UsageLogDecoder *decoder) {
    if (!decoder) return;
    if (decoder->file) fclose(decoder->file);
    if (decoder->stream) ZSTD_freeDStream(decoder->stream);
    free(decoder);
}
