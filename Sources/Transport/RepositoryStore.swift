import Foundation
import GitKit

/// Low-level read/write access to a repository's object and reference storage,
/// writing loose objects in a GitKit-compatible (stored-block zlib) format.
struct RepositoryStore {
    let gitDir: URL

    private var objectsDir: URL { gitDir.appendingPathComponent("objects") }

    init(gitDir: URL) {
        self.gitDir = gitDir
    }

    // MARK: - Objects

    /// Writes a raw object as a loose object and returns its OID.
    @discardableResult
    func writeObject(type: GKObjectType, data: Data) throws -> GKObjectID {
        let raw = GKRawObject(type: type, data: data)
        let hex = raw.oid.hex
        let dir = objectsDir.appendingPathComponent(String(hex.prefix(2)))
        let file = dir.appendingPathComponent(String(hex.dropFirst(2)))

        if FileManager.default.fileExists(atPath: file.path) { return raw.oid }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let compressed = Zlib.compressStored(raw.serialized)
        try compressed.write(to: file)
        return raw.oid
    }

    /// Reads a loose object, if present, returning its type and content.
    func readLooseObject(_ oid: GKObjectID) -> (GKObjectType, Data)? {
        let hex = oid.hex
        let file = objectsDir
            .appendingPathComponent(String(hex.prefix(2)))
            .appendingPathComponent(String(hex.dropFirst(2)))
        guard let compressed = try? Data(contentsOf: file),
              let decompressed = try? Zlib.inflateAll(compressed),
              let nul = decompressed.firstIndex(of: 0) else { return nil }

        let header = String(data: decompressed[..<nul], encoding: .ascii) ?? ""
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let type = GKObjectType(rawValue: String(parts[0])) else { return nil }
        let content = Data(decompressed[(decompressed.index(after: nul))...])
        return (type, content)
    }

    // MARK: - References

    /// Writes (or updates) a reference to point at the given OID.
    func writeReference(_ name: String, oid: GKObjectID) throws {
        let file = gitDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(oid.hex)\n".utf8).write(to: file)
    }

    /// Points HEAD at a branch via a symbolic reference.
    func setHeadSymbolic(toBranch branch: String) throws {
        let head = gitDir.appendingPathComponent("HEAD")
        try Data("ref: refs/heads/\(branch)\n".utf8).write(to: head)
    }

    /// Lists local reference OIDs (loose refs under refs/), for fetch negotiation.
    func localRefOIDs() -> [GKObjectID] {
        let refsDir = gitDir.appendingPathComponent("refs")
        guard let enumerator = FileManager.default.enumerator(
                at: refsDir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }

        var oids: [GKObjectID] = []
        for case let url as URL in enumerator {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let hex = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if let oid = GKObjectID(hex: hex) { oids.append(oid) }
        }
        return oids
    }

    /// Reads a single reference's OID, if it exists as a loose ref.
    func readReference(_ name: String) -> GKObjectID? {
        let file = gitDir.appendingPathComponent(name)
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return GKObjectID(hex: contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Remote configuration

    /// Adds a remote to `.git/config` using a correctly-formatted section.
    /// (Written directly to work around a serialization bug in GitKit's config.)
    func writeRemote(name: String, url: String) throws {
        let configURL = gitDir.appendingPathComponent("config")
        var text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if text.contains("[remote \"\(name)\"]") { return }
        if !text.hasSuffix("\n") && !text.isEmpty { text += "\n" }
        text += "[remote \"\(name)\"]\n"
        text += "\turl = \(url)\n"
        text += "\tfetch = +refs/heads/*:refs/remotes/\(name)/*\n"
        try Data(text.utf8).write(to: configURL)
    }

    /// Reads a remote's URL from `.git/config`, if configured.
    func readRemoteURL(name: String) -> String? {
        let configURL = gitDir.appendingPathComponent("config")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }

        var inSection = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = (line == "[remote \"\(name)\"]")
            } else if inSection, line.hasPrefix("url") {
                if let eq = line.firstIndex(of: "=") {
                    return String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}
