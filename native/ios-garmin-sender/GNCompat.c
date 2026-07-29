#include <stddef.h>

void *memset(void *dst, int value, size_t length) {
    unsigned char *out = (unsigned char *)dst;
    while (length--) {
        *out++ = (unsigned char)value;
    }
    return dst;
}

void *memcpy(void *dst, const void *src, size_t length) {
    unsigned char *out = (unsigned char *)dst;
    const unsigned char *in = (const unsigned char *)src;
    while (length--) {
        *out++ = *in++;
    }
    return dst;
}

void *memmove(void *dst, const void *src, size_t length) {
    unsigned char *out = (unsigned char *)dst;
    const unsigned char *in = (const unsigned char *)src;

    if (out == in || length == 0) {
        return dst;
    }

    if (out < in) {
        while (length--) {
            *out++ = *in++;
        }
    } else {
        out += length;
        in += length;
        while (length--) {
            *--out = *--in;
        }
    }

    return dst;
}
