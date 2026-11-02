#include <compression.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// ExifTool's Brotli hooks use bounded temporary files, never the photo itself.
int main(int argc, char **argv) {
    if (argc != 5 || (strcmp(argv[1], "encode") && strcmp(argv[1], "decode"))) return 2;
    char *end = NULL;
    unsigned long long limit = strtoull(argv[4], &end, 10);
    if (!end || *end || !limit || limit > 100000000) return 2;
    FILE *input = fopen(argv[2], "rb");
    if (!input) return 2;
    struct stat info;
    if (fstat(fileno(input), &info) || info.st_size <= 0 || info.st_size > 100000000) {
        fclose(input); return 2;
    }
    size_t size = (size_t)info.st_size;
    unsigned char *source = malloc(size);
    if (!source) { fclose(input); return 2; }
    if (fread(source, 1, size, input) != size) { free(source); fclose(input); return 2; }
    fclose(input);
    int encoding = !strcmp(argv[1], "encode");
    size_t capacity = encoding ? size * 2 + 1024 : (size_t)limit;
    if (capacity > limit) capacity = (size_t)limit;
    unsigned char *destination = malloc(capacity);
    if (!destination) { free(source); return 2; }
    size_t count = encoding ? compression_encode_buffer(destination, capacity, source, size, NULL, COMPRESSION_BROTLI)
                            : compression_decode_buffer(destination, capacity, source, size, NULL, COMPRESSION_BROTLI);
    free(source);
    if (!count || count >= capacity) { free(destination); return 2; }
    FILE *output = fopen(argv[3], "wb");
    if (!output) { free(destination); return 2; }
    int success = fwrite(destination, 1, count, output) == count;
    if (fclose(output)) success = 0;
    free(destination);
    return success ? 0 : 2;
}
