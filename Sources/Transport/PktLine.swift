import Foundation

/// Encoder/decoder for Git's pkt-line wire format.
///
/// A pkt-line is a 4-byte hex length prefix followed by the payload. The length
/// includes the 4 header bytes. Special lengths: `0000` is a flush packet and
/// `0001` is a delimiter packet (protocol v2).
enum PktLine {
    static let flush = Data("0000".utf8)
    static let delim = Data("0001".utf8)

    /// Encodes a payload as a single pkt-line.
    static func encode(_ payload: Data) -> Data {
        let length = payload.count + 4
        precondition(length <= 0xFFFF, "pkt-line payload too large")
        let header = String(format: "%04x", length)
        return Data(header.utf8) + payload
    }

    /// Encodes a string payload as a pkt-line.
    static func encode(_ string: String) -> Data {
        encode(Data(string.utf8))
    }

    /// A decoded pkt-line.
    enum Packet {
        case flush
        case delim
        case data(Data)
    }

    /// Parses a complete buffer of pkt-lines into packets.
    /// Returns the parsed packets and the number of bytes consumed.
    static func parse(_ buffer: Data) -> (packets: [Packet], consumed: Int) {
        var packets: [Packet] = []
        var index = buffer.startIndex

        while buffer.distance(from: index, to: buffer.endIndex) >= 4 {
            let header = buffer[index..<buffer.index(index, offsetBy: 4)]
            guard let lengthString = String(data: header, encoding: .ascii),
                  let length = Int(lengthString, radix: 16) else {
                break
            }

            switch length {
            case 0:
                packets.append(.flush)
                index = buffer.index(index, offsetBy: 4)
                continue
            case 1:
                packets.append(.delim)
                index = buffer.index(index, offsetBy: 4)
                continue
            default:
                break
            }

            // Need the full packet available.
            guard buffer.distance(from: index, to: buffer.endIndex) >= length else {
                break
            }

            let payloadStart = buffer.index(index, offsetBy: 4)
            let payloadEnd = buffer.index(index, offsetBy: length)
            packets.append(.data(Data(buffer[payloadStart..<payloadEnd])))
            index = payloadEnd
        }

        return (packets, buffer.distance(from: buffer.startIndex, to: index))
    }

    /// Returns the payload of a `.data` packet, or nil otherwise.
    static func payload(_ packet: Packet) -> Data? {
        if case .data(let data) = packet { return data }
        return nil
    }
}
