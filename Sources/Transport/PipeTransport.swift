import Foundation
import GitKit

/// The Git wire service being spoken over a transport.
enum GitService {
    case uploadPack   // fetch / clone
    case receivePack  // push

    var commandName: String {
        switch self {
        case .uploadPack: return "git-upload-pack"
        case .receivePack: return "git-receive-pack"
        }
    }

    var httpService: String {
        switch self {
        case .uploadPack: return "git-upload-pack"
        case .receivePack: return "git-receive-pack"
        }
    }
}

/// A `GKTransport` that speaks the Git protocol over a long-lived subprocess
/// pipe (stdin/stdout). Used by both the SSH and local-filesystem transports,
/// which differ only in the command they launch.
class PipeTransport: GKTransport {
    let executable: URL
    let arguments: [String]
    let service: GitService

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var advertisement: GitWireProtocol.Advertisement?

    init(executable: URL, arguments: [String], service: GitService) {
        self.executable = executable
        self.arguments = arguments
        self.service = service
    }

    // MARK: - GKTransport

    func connect() throws -> GKRemoteAdvertisement {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw SGitError.unsupported("failed to launch \(executable.lastPathComponent): \(error.localizedDescription)")
        }

        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Read the reference advertisement up to its terminating flush packet.
        let advData = try readAdvertisement(from: stdout.fileHandleForReading)
        let parsed = GitWireProtocol.parseAdvertisement(advData)
        self.advertisement = parsed

        return GKRemoteAdvertisement(
            references: parsed.references,
            capabilities: parsed.capabilities,
            head: parsed.head
        )
    }

    func fetch(wants: [GKObjectID], haves: [GKObjectID]) throws -> Data {
        guard let stdin = stdinPipe, let stdout = stdoutPipe else {
            throw SGitError.unsupported("transport not connected")
        }
        let capabilities = advertisement?.capabilities ?? []
        let request = GitWireProtocol.buildUploadPackRequest(
            wants: wants, haves: haves, serverCapabilities: capabilities)

        stdin.fileHandleForWriting.write(request)
        try? stdin.fileHandleForWriting.close()

        let response = stdout.fileHandleForReading.readDataToEndOfFile()
        try waitAndCheck()
        return try GitWireProtocol.extractPackfile(from: response)
    }

    func push(commands: [GKPushCommand], packData: Data) throws -> [GKPushResult] {
        guard let stdin = stdinPipe, let stdout = stdoutPipe else {
            throw SGitError.unsupported("transport not connected")
        }
        let capabilities = advertisement?.capabilities ?? []
        let request = GitWireProtocol.buildReceivePackRequest(
            commands: commands, packData: packData, serverCapabilities: capabilities)

        stdin.fileHandleForWriting.write(request)
        try? stdin.fileHandleForWriting.close()

        let response = stdout.fileHandleForReading.readDataToEndOfFile()
        try waitAndCheck()
        return GitWireProtocol.parseReportStatus(response, commands: commands)
    }

    // MARK: - Helpers

    /// Reads from the stream until the advertisement's terminating flush packet.
    private func readAdvertisement(from handle: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF
            buffer.append(chunk)

            // Stop once a flush packet that terminates the ref list is seen.
            if sawTerminatingFlush(buffer) { break }
        }
        return buffer
    }

    /// Returns true when the buffer contains a flush packet after at least one
    /// real ref line (smart HTTP also emits a flush right after the banner).
    private func sawTerminatingFlush(_ buffer: Data) -> Bool {
        let (packets, _) = PktLine.parse(buffer)
        var sawRef = false
        for packet in packets {
            switch packet {
            case .flush where sawRef:
                return true
            case .data(let payload):
                let text = String(data: payload, encoding: .utf8) ?? ""
                if !text.hasPrefix("#") { sawRef = true }
            default:
                break
            }
        }
        return false
    }

    private func waitAndCheck() throws {
        guard let process else { return }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let message = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw SGitError.unsupported("remote process failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
