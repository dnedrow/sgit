import Foundation
import GitKit

/// Orchestrates network operations (clone, fetch, pull, push) on top of the
/// `GKTransport` implementations. Object materialization is done natively here
/// because GitKit's bundled inflater/unpacker only handles stored blocks.
enum RemoteService {
    // MARK: - Clone

    static func clone(url: String, into destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path),
           let contents = try? fm.contentsOfDirectory(atPath: destination.path),
           !contents.isEmpty {
            throw SGitError.invalidArgument("destination path '\(destination.lastPathComponent)' already exists and is not empty")
        }

        Terminal.print("Cloning into '\(destination.lastPathComponent)'...")

        let transport = try TransportFactory.makeTransport(for: url, service: .uploadPack)
        let advertisement = try transport.connect()

        guard !advertisement.references.isEmpty else {
            throw SGitError.unsupported("remote has no references (empty repository?)")
        }

        // Want every advertised tip.
        var wantSet = Set<GKObjectID>()
        for ref in advertisement.references { if let oid = ref.target.oid { wantSet.insert(oid) } }
        if let head = advertisement.head { wantSet.insert(head) }

        let packData = try transport.fetch(wants: Array(wantSet), haves: [])

        // Initialize the repository and write objects natively.
        let repo = try GKRepository.GKInitRepository(at: destination)
        let store = RepositoryStore(gitDir: repo.gitDir)

        let written = try applyPack(packData, store: store)
        Terminal.print("Received \(written) object(s).")

        // Mirror the remote's refs and set up remote-tracking refs.
        for ref in advertisement.references {
            guard let oid = ref.target.oid else { continue }
            try store.writeReference(ref.name, oid: oid)
            if ref.isBranch {
                try store.writeReference("refs/remotes/origin/\(ref.shortName)", oid: oid)
            }
        }

        let defaultBranch = defaultBranchName(advertisement)
        try store.setHeadSymbolic(toBranch: defaultBranch)
        try store.writeRemote(name: "origin", url: url)

        // Check out the working tree for the default branch.
        let reopened = try GKRepository(at: destination)
        try reopened.GKCheckout(branch: defaultBranch)
        Terminal.print("Checked out branch '\(defaultBranch)'.")
    }

    // MARK: - Fetch

    @discardableResult
    static func fetch(repo: GKRepository, remoteName: String, url: String) throws -> [GKReference] {
        let store = RepositoryStore(gitDir: repo.gitDir)

        let transport = try TransportFactory.makeTransport(for: url, service: .uploadPack)
        let advertisement = try transport.connect()

        // Want advertised tips we don't already have locally.
        var wantSet = Set<GKObjectID>()
        for ref in advertisement.references where ref.isBranch || ref.isTag {
            guard let oid = ref.target.oid else { continue }
            if store.readLooseObject(oid) == nil { wantSet.insert(oid) }
        }

        if !wantSet.isEmpty {
            let haves = store.localRefOIDs()
            let packData = try transport.fetch(wants: Array(wantSet), haves: haves)
            let written = try applyPack(packData, store: store)
            Terminal.print("Received \(written) object(s) from \(remoteName).")
        } else {
            Terminal.print("Already up to date.")
        }

        // Update remote-tracking references.
        var updated: [GKReference] = []
        for ref in advertisement.references where ref.isBranch {
            guard let oid = ref.target.oid else { continue }
            try store.writeReference("refs/remotes/\(remoteName)/\(ref.shortName)", oid: oid)
            updated.append(ref)
        }
        return updated
    }

    // MARK: - Pull (fetch + fast-forward)

    static func pull(repo: GKRepository, remoteName: String, url: String) throws {
        _ = try fetch(repo: repo, remoteName: remoteName, url: url)
        let store = RepositoryStore(gitDir: repo.gitDir)

        guard let branch = try repo.head().branchName else {
            throw SGitError.unsupported("cannot pull with a detached HEAD")
        }
        guard let remoteOID = store.readReference("refs/remotes/\(remoteName)/\(branch)") else {
            throw SGitError.unsupported("remote branch '\(remoteName)/\(branch)' not found")
        }

        let localOID = try? repo.GKHeadCommitOID()
        if localOID == remoteOID {
            Terminal.print("Already up to date.")
            return
        }

        // Fast-forward the current branch and update the working tree.
        try store.writeReference("refs/heads/\(branch)", oid: remoteOID)
        let reopened = try GKRepository(at: repo.workDir)
        try reopened.GKCheckout(branch: branch)
        Terminal.print("Fast-forwarded \(branch) to \(String(remoteOID.hex.prefix(7))).")
    }

    // MARK: - Push

    static func push(repo: GKRepository, remoteName: String, url: String, branch: String) throws {
        let transport = try TransportFactory.makeTransport(for: url, service: .receivePack)
        // GitKit builds the packfile (stored-block zlib, which servers accept)
        // and drives the push handshake through our transport.
        try repo.GKPush(remote: remoteName, branch: branch, transport: transport)
        Terminal.print("Pushed \(branch) to \(remoteName).")
    }

    // MARK: - Helpers

    /// Decodes a packfile and writes every object as a loose object.
    private static func applyPack(_ packData: Data, store: RepositoryStore) throws -> Int {
        let reader = PackReader(pack: packData) { oid in
            store.readLooseObject(oid)
        }
        let objects = try reader.parse()
        for object in objects {
            try store.writeObject(type: object.type, data: object.data)
        }
        return objects.count
    }

    /// Determines the default branch to check out after a clone.
    private static func defaultBranchName(_ advertisement: GKRemoteAdvertisement) -> String {
        if let head = advertisement.head,
           let match = advertisement.references.first(where: { $0.isBranch && $0.target.oid == head }) {
            return match.shortName
        }
        if advertisement.references.contains(where: { $0.name == "refs/heads/main" }) { return "main" }
        if advertisement.references.contains(where: { $0.name == "refs/heads/master" }) { return "master" }
        return advertisement.references.first(where: { $0.isBranch })?.shortName ?? "main"
    }
}
