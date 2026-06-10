#ifndef SGIT_BRIDGING_HEADER_H
#define SGIT_BRIDGING_HEADER_H

#include <zlib.h>

// Thin wrappers around zlib's macro-based initializers so they can be called
// from Swift. zlib decodes the full zlib stream (2-byte header + DEFLATE +
// Adler-32) and reports `total_in`, which we use to find packfile object
// boundaries precisely.
static inline int gk_inflate_init(z_streamp strm) {
    return inflateInit(strm);
}

static inline int gk_inflate(z_streamp strm) {
    return inflate(strm, Z_NO_FLUSH);
}

static inline int gk_inflate_end(z_streamp strm) {
    return inflateEnd(strm);
}

#endif /* SGIT_BRIDGING_HEADER_H */
