import Foundation
import GitKit

/// Implements the Git "smart" wire protocol (v0): reference advertisement
/// parsing, upload-pack (fetch) requests, and receive-pack (push) requests.
enum GitWireProtocol {

    /// The parsed result of a reference advertisement.
    struct Advertisement {
        var references: [GKReference]
        var capabilities: [String]
        var head: GKObjectID?
    }

    /// Parses a reference advertisement from upload-pack or receive-pack.
    /// Handles the optional `# service=...` banner used by smart HTTP.
    static func parseAdvertisement(_ data: Data) -> Advertisement {
        let (packets, _) = PktLine.parse(data)

        var references: [GKReference] = []
        var capabilities: [String] = []
        var head: GKObjectID?
        var symHead: String?

        for packet in packets {
            guard let payload = PktLine.payload(packet) else { continue }
            guard var line = String(data: payload, encoding: .utf8) else { continue }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))

            // Skip the smart-HTTP service banner ("# service=git-upload-pack").
            if line.hasPrefix("#") { continue }

            // The first ref line carries capabilities after a NUL byte.
            var refPart = line
            if let nul = line.firstIndex(of: "\0") {
                refPart = String(line[line.startIndex..<nul])
                let capString = String(line[line.index(after: nul)...])
                capabilities = capString.split(separator: " ").map(String.init)
                // Discover the symref HEAD points to, if advertised.
                for cap in capabilities where cap.hasPrefix("symref=HEAD:") {
                    symHead = String(cap.dropFirst("symref=HEAD:".count))
                }
            }

            let fields = refPart.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2, let oid = GKObjectID(hex: fields[0]) else { continue }
            let name = fields[1]

            if name == "HEAD" {
                head = oid
                continue
            }
            // Ignore peeled tag entries ("refs/tags/x^{}").
            if name.hasSuffix("^{}") { continue }

            references.append(GKReference(name: name, target: .direct(oid)))
        }

        // Prefer the symref target's OID for HEAD when available.
        if let symHead, let match = references.first(where: { $0.name == symHead }) {
            head = match.target.oid
        }

        return Advertisement(references: references, capabilities: capabilities, head: head)
    }

    /// Builds an upload-pack request body for the given wants/haves.
    static func buildUploadPackRequest(
        wants: [GKObjectID],
        haves: [GKObjectID],
        serverCapabilities: [String]
    ) -> Data {
        // Negotiate only capabilities we actually support.
        let desired = ["ofs-delta", "agent=sgit/1.0"]
        let supported = desired.filter { cap in
            if cap.hasPrefix("agent=") { return true }
            return serverCapabilities.contains(cap)
        }
        let capLine = supported.joined(separator: " ")

        var body = Data()
        for (index, oid) in wants.enumerated() {
            if index == 0 {
                body.append(PktLine.encode("want \(oid.hex) \(capLine)\n"))
            } else {
                body.append(PktLine.encode("want \(oid.hex)\n"))
            }
        }
        body.append(PktLine.flush)

        for have in haves {
            body.append(PktLine.encode("have \(have.hex)\n"))
        }
        body.append(PktLine.encode("done\n"))
        return body
    }

    /// Extracts the raw packfile from an upload-pack response. Since we do not
    /// negotiate side-band, the packfile follows the NAK/ACK line verbatim.
    static func extractPackfile(from response: Data) throws -> Data {
        var index = response.startIndex

        while response.distance(from: index, to: response.endIndex) >= 4 {
            let header = response[index..<response.index(index, offsetBy: 4)]
            guard let lengthString = String(data: header, encoding: .ascii),
                  let length = Int(lengthString, radix: 16) else {
                break
            }

            if length == 0 || length == 1 {
                index = response.index(index, offsetBy: 4)
                continue
            }
            guard response.distance(from: index, to: response.endIndex) >= length else { break }

            let payloadStart = response.index(index, offsetBy: 4)
            let payloadEnd = response.index(index, offsetBy: length)
            let payload = response[payloadStart..<payloadEnd]
            let text = String(data: payload, encoding: .utf8) ?? ""

            index = payloadEnd

            if text.hasPrefix("NAK") || text.hasPrefix("ACK") {
                // The packfile begins immediately after this control line.
                return Data(response[index..<response.endIndex])
            }
            // Otherwise skip shallow/comment lines and keep scanning.
        }

        // Fallback: locate the "PACK" signature directly.
        if let range = response.range(of: Data("PACK".utf8)) {
            return Data(response[range.lowerBound..<response.endIndex])
        }

        throw SGitError.invalidArgument("no packfile found in server response")
    }

    /// Builds a receive-pack request: ref update commands followed by the pack.
    static func buildReceivePackRequest(
        commands: [GKPushCommand],
        packData: Data,
        serverCapabilities: [String]
    ) -> Data {
        let desired = ["report-status", "agent=sgit/1.0"]
        let supported = desired.filter { cap in
            if cap.hasPrefix("agent=") { return true }
            return serverCapabilities.contains(cap)
        }
        let capLine = supported.joined(separator: " ")

        var body = Data()
        for (index, command) in commands.enumerated() {
            let line = "\(command.oldOID.hex) \(command.newOID.hex) \(command.refName)"
            if index == 0 {
                body.append(PktLine.encode("\(line)\0\(capLine)\n"))
            } else {
                body.append(PktLine.encode("\(line)\n"))
            }
        }
        body.append(PktLine.flush)
        // Only send a packfile when there are objects to transfer (not for deletes).
        if !packData.isEmpty {
            body.append(packData)
        }
        return body
    }

    /// Parses a receive-pack report-status response into push results.
    static func parseReportStatus(_ data: Data, commands: [GKPushCommand]) -> [GKPushResult] {
        let (packets, _) = PktLine.parse(data)
        var unpackOK = true
        var perRef: [String: (Bool, String?)] = [:]

        for packet in packets {
            guard let payload = PktLine.payload(packet),
                  let line = String(data: payload, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\n")) else { continue }

            if line.hasPrefix("unpack ") {
                unpackOK = (line == "unpack ok")
            } else if line.hasPrefix("ok ") {
                perRef[String(line.dropFirst(3))] = (true, nil)
            } else if line.hasPrefix("ng ") {
                let rest = String(line.dropFirst(3))
                let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
                let ref = parts.first ?? rest
                let reason = parts.count > 1 ? parts[1] : "rejected"
                perRef[ref] = (false, reason)
            }
        }

        return commands.map { command in
            if let status = perRef[command.refName] {
                return GKPushResult(refName: command.refName, success: status.0 && unpackOK, message: status.1)
            }
            // No explicit status (server may omit report-status): assume unpack result.
            return GKPushResult(
                refName: command.refName,
                success: unpackOK,
                message: unpackOK ? nil : "unpack failed"
            )
        }
    }
}
