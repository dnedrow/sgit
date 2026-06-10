import Foundation

/// Zlib (RFC 1950) helpers.
///
/// Decompression uses the system `zlib` library (via bridged wrappers), which
/// natively understands the full zlib stream — 2-byte header, DEFLATE body, and
/// trailing Adler-32 — and reports `total_in`. That byte-accurate consumption
/// count is essential for walking consecutive objects inside a packfile.
enum Zlib {

    struct InflateResult {
        let data: Data
        /// Number of input bytes consumed (the complete zlib stream length).
        let consumed: Int
    }

    /// Inflates a zlib stream beginning at `offset` within `input`.
    /// - Parameters:
    ///   - input: The buffer containing the zlib stream.
    ///   - offset: Start of the zlib stream (the 2-byte header).
    ///   - expectedSize: The known uncompressed size, used to size the buffer.
    static func inflate(_ input: Data, at offset: Int, expectedSize: Int) throws -> InflateResult {
        guard offset < input.count else {
            throw SGitError.invalidArgument("truncated zlib stream")
        }

        var strm = z_stream()
        guard gk_inflate_init(&strm) == Z_OK else {
            throw SGitError.invalidArgument("failed to initialize zlib")
        }
        defer { gk_inflate_end(&strm) }

        var output = Data(capacity: min(max(expectedSize, 64), 1 << 20))
        let outBufferSize = 64 * 1024
        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outBufferSize)
        defer { outBuffer.deallocate() }

        var status: Int32 = Z_OK

        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            strm.next_in = UnsafeMutablePointer(mutating: base.advanced(by: offset))
            strm.avail_in = uInt(input.count - offset)

            repeat {
                strm.next_out = outBuffer
                strm.avail_out = uInt(outBufferSize)
                status = gk_inflate(&strm)

                if status != Z_OK && status != Z_STREAM_END {
                    throw SGitError.invalidArgument("zlib inflate failed (\(status))")
                }
                let produced = outBufferSize - Int(strm.avail_out)
                output.append(outBuffer, count: produced)
            } while status != Z_STREAM_END
        }

        return InflateResult(data: output, consumed: Int(strm.total_in))
    }

    /// Inflates a complete, standalone zlib stream (e.g. a loose object file).
    static func inflateAll(_ input: Data) throws -> Data {
        try inflate(input, at: 0, expectedSize: Int.max).data
    }

    /// Compresses data into a zlib stream using *stored* (uncompressed) DEFLATE
    /// blocks. This mirrors GitKit's own `GKZlib.compress`, ensuring objects
    /// written by sgit remain readable by GitKit's (stored-block-only) inflater.
    static func compressStored(_ data: Data) -> Data {
        var result = Data()
        result.append(0x78) // CMF: deflate, 32K window
        result.append(0x01) // FLG: level 0, valid header checksum (0x7801 % 31 == 0)

        let bytes = [UInt8](data)
        if bytes.isEmpty {
            result.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF])
        } else {
            var offset = 0
            while offset < bytes.count {
                let blockSize = min(bytes.count - offset, 0xFFFF)
                let isFinal: UInt8 = (offset + blockSize >= bytes.count) ? 0x01 : 0x00
                result.append(isFinal) // BFINAL + BTYPE=00
                let len = UInt16(blockSize)
                let nlen = ~len
                result.append(UInt8(len & 0xFF))
                result.append(UInt8(len >> 8))
                result.append(UInt8(nlen & 0xFF))
                result.append(UInt8(nlen >> 8))
                result.append(contentsOf: bytes[offset..<offset + blockSize])
                offset += blockSize
            }
        }

        let checksum = adler32(data)
        result.append(UInt8((checksum >> 24) & 0xFF))
        result.append(UInt8((checksum >> 16) & 0xFF))
        result.append(UInt8((checksum >> 8) & 0xFF))
        result.append(UInt8(checksum & 0xFF))
        return result
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        let mod: UInt32 = 65521
        for byte in data {
            a = (a + UInt32(byte)) % mod
            b = (b + a) % mod
        }
        return (b << 16) | a
    }
}
