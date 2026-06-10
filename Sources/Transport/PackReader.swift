import Foundation
import GitKit

/// Parses a Git packfile into fully-materialized objects, resolving both
/// `OFS_DELTA` and `REF_DELTA` entries. GitKit cannot do this (its inflater only
/// supports stored blocks), so sgit implements it natively.
struct PackReader {

    struct Object {
        let type: GKObjectType
        let data: Data
        let oid: GKObjectID
    }

    /// Provides base objects that live outside the pack (for thin packs / fetch).
    var baseProvider: ((GKObjectID) -> (GKObjectType, Data)?)?

    private let pack: [UInt8]

    init(pack: Data, baseProvider: ((GKObjectID) -> (GKObjectType, Data)?)? = nil) {
        self.pack = [UInt8](pack)
        self.baseProvider = baseProvider
    }

    /// Parses the pack and returns all contained objects.
    func parse() throws -> [Object] {
        guard pack.count >= 12,
              pack[0] == 0x50, pack[1] == 0x41, pack[2] == 0x43, pack[3] == 0x4B else { // "PACK"
            throw SGitError.invalidArgument("invalid packfile header")
        }

        let version = readUInt32(at: 4)
        guard version == 2 || version == 3 else {
            throw SGitError.invalidArgument("unsupported packfile version \(version)")
        }
        let objectCount = Int(readUInt32(at: 8))

        var offset = 12
        var byOffset: [Int: (GKObjectType, Data)] = [:]
        var byOID: [GKObjectID: (GKObjectType, Data)] = [:]
        var results: [Object] = []

        for i in 0..<objectCount {
            guard offset < pack.count else {
                throw SGitError.invalidArgument("pack truncated at object \(i)/\(objectCount)")
            }
            let objectStart = offset
            let (rawType, size, headerLength) = readObjectHeader(at: offset)
            offset += headerLength

            switch rawType {
            case 1, 2, 3, 4:
                let type = objectType(for: rawType)!
                let inflated = try Zlib.inflate(Data(pack), at: offset, expectedSize: size)
                offset += inflated.consumed
                store(type, inflated.data, at: objectStart,
                      byOffset: &byOffset, byOID: &byOID, results: &results)

            case 6: // OFS_DELTA
                let (relativeOffset, ofsLength) = readOffset(at: offset)
                offset += ofsLength
                let inflated = try Zlib.inflate(Data(pack), at: offset, expectedSize: size)
                offset += inflated.consumed
                let baseOffset = objectStart - relativeOffset
                guard let base = byOffset[baseOffset] else {
                    throw SGitError.invalidArgument("missing OFS_DELTA base")
                }
                let resolved = try applyDelta(base: base.1, delta: inflated.data)
                store(base.0, resolved, at: objectStart,
                      byOffset: &byOffset, byOID: &byOID, results: &results)

            case 7: // REF_DELTA
                guard offset + 20 <= pack.count else {
                    throw SGitError.invalidArgument("truncated REF_DELTA base id")
                }
                let baseOID = GKObjectID(bytes: Array(pack[offset..<offset + 20]))
                offset += 20
                let inflated = try Zlib.inflate(Data(pack), at: offset, expectedSize: size)
                offset += inflated.consumed
                let base = byOID[baseOID] ?? baseProvider?(baseOID)
                guard let base else {
                    throw SGitError.invalidArgument("missing REF_DELTA base \(baseOID.hex)")
                }
                let resolved = try applyDelta(base: base.1, delta: inflated.data)
                store(base.0, resolved, at: objectStart,
                      byOffset: &byOffset, byOID: &byOID, results: &results)

            default:
                throw SGitError.invalidArgument("unknown pack object type \(rawType)")
            }
        }

        return results
    }

    // MARK: - Storage

    private func store(
        _ type: GKObjectType,
        _ data: Data,
        at offset: Int,
        byOffset: inout [Int: (GKObjectType, Data)],
        byOID: inout [GKObjectID: (GKObjectType, Data)],
        results: inout [Object]
    ) {
        let oid = GKRawObject.computeOID(type: type, data: data)
        byOffset[offset] = (type, data)
        byOID[oid] = (type, data)
        results.append(Object(type: type, data: data, oid: oid))
    }

    // MARK: - Header parsing

    /// Reads the variable-length object header: (rawType, uncompressedSize, byteLength).
    private func readObjectHeader(at start: Int) -> (Int, Int, Int) {
        var index = start
        let first = pack[index]
        index += 1
        let rawType = Int((first >> 4) & 0x07)
        var size = Int(first & 0x0F)
        var shift = 4
        var byte = first
        while byte & 0x80 != 0 {
            byte = pack[index]
            index += 1
            size |= Int(byte & 0x7F) << shift
            shift += 7
        }
        return (rawType, size, index - start)
    }

    /// Reads an OFS_DELTA negative base offset: (offset, byteLength).
    private func readOffset(at start: Int) -> (Int, Int) {
        var index = start
        var byte = pack[index]
        index += 1
        var value = Int(byte & 0x7F)
        while byte & 0x80 != 0 {
            byte = pack[index]
            index += 1
            value = ((value + 1) << 7) | Int(byte & 0x7F)
        }
        return (value, index - start)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(pack[offset]) << 24 | UInt32(pack[offset + 1]) << 16 |
        UInt32(pack[offset + 2]) << 8 | UInt32(pack[offset + 3])
    }

    private func objectType(for raw: Int) -> GKObjectType? {
        switch raw {
        case 1: return .commit
        case 2: return .tree
        case 3: return .blob
        case 4: return .tag
        default: return nil
        }
    }

    // MARK: - Delta application

    /// Applies a Git delta to a base object, producing the target object.
    private func applyDelta(base: Data, delta: Data) throws -> Data {
        let d = [UInt8](delta)
        var index = 0

        // Base size and result size are LEB128-encoded.
        let (_, baseLen) = readVarint(d, at: index); index += baseLen
        let (targetSize, targetLen) = readVarint(d, at: index); index += targetLen

        let baseBytes = [UInt8](base)
        var output = [UInt8]()
        output.reserveCapacity(targetSize)

        while index < d.count {
            let opcode = d[index]; index += 1

            if opcode & 0x80 != 0 {
                // Copy from base: variable offset and size fields follow.
                var copyOffset = 0
                var copySize = 0
                if opcode & 0x01 != 0 { copyOffset |= Int(d[index]); index += 1 }
                if opcode & 0x02 != 0 { copyOffset |= Int(d[index]) << 8; index += 1 }
                if opcode & 0x04 != 0 { copyOffset |= Int(d[index]) << 16; index += 1 }
                if opcode & 0x08 != 0 { copyOffset |= Int(d[index]) << 24; index += 1 }
                if opcode & 0x10 != 0 { copySize |= Int(d[index]); index += 1 }
                if opcode & 0x20 != 0 { copySize |= Int(d[index]) << 8; index += 1 }
                if opcode & 0x40 != 0 { copySize |= Int(d[index]) << 16; index += 1 }
                if copySize == 0 { copySize = 0x10000 }
                guard copyOffset + copySize <= baseBytes.count else {
                    throw SGitError.invalidArgument("delta copy out of bounds")
                }
                output.append(contentsOf: baseBytes[copyOffset..<copyOffset + copySize])
            } else if opcode != 0 {
                // Insert literal bytes from the delta stream.
                let count = Int(opcode)
                guard index + count <= d.count else {
                    throw SGitError.invalidArgument("delta insert out of bounds")
                }
                output.append(contentsOf: d[index..<index + count])
                index += count
            } else {
                throw SGitError.invalidArgument("invalid delta opcode 0x00")
            }
        }

        return Data(output)
    }

    /// Reads a little-endian base-128 varint: (value, byteLength).
    private func readVarint(_ bytes: [UInt8], at start: Int) -> (Int, Int) {
        var index = start
        var value = 0
        var shift = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return (value, index - start)
    }
}
