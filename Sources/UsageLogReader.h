#ifndef USAGE_LOG_READER_H
#define USAGE_LOG_READER_H
#include <stddef.h>
#include <stdint.h>

typedef struct UsageLogDecoder UsageLogDecoder;
UsageLogDecoder *usage_log_open(const char *path);
int64_t usage_log_read(UsageLogDecoder *decoder, void *destination, size_t capacity);
void usage_log_close(UsageLogDecoder *decoder);
#endif
