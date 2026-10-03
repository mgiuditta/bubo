import CryptoKit
import DeliveryKit
import Foundation

/// The receiver's side of a Consegna (spec 24, Destinatario): checks header and sender, decrypts and extracts the
/// content before anything is shown; at Metti tra le Bozze imports the branch as `consegna/‹mittente›/‹nome›`; at
/// Avvia writes the conversation for the receiver's worktree; at Scarta deletes what the Consegna left.
nonisolated struct DeliveryOpener: Sendable {
    /// Why a Consegna does not open: one text of the foglio "Non si apre" each.
    enum Failure: Error, Equatable {
        /// Encrypted for another Macchina's key: `machine` when a Biglietto names it, `sender` when one names who sent it.
        case otherMachine(machine: String?, sender: String?)
        /// No verified Biglietto has the sender's key.
        case unknownSender
        /// The authentication does not pass, or the content is not a Consegna's: changed, cut or damaged.
        case damaged(sender: String?)
        /// The branch starts from commits this Mac does not have, even after `git fetch`.
        case baseUnreachable(sender: String, branch: String?)
        /// This Mac's key does not open, or the content cannot be written: nothing about the file.
        case unavailable
    }

    /// A Consegna verified and decrypted, ready for the foglio "Consegna ricevuta".
    struct Opened: Equatable, Sendable {
        let manifest: DeliveryManifest
        /// `Consegne/<id>/`: the content in the clear.
        let folder: URL
        /// The verified Biglietto of who sent it.
        let sender: ReceivedTicket
    }

    /// Where the content of the Consegne waits in the clear, one folder per Consegna id, until Avvia or Scarta.
    var root = URL.applicationSupportDirectory.appending(path: "Bubo/Consegne", directoryHint: .isDirectory)
    /// Runs git.
    var runner = ProcessRunner.live

    private static let git = URL(filePath: "/usr/bin/git")

    /// The verified Biglietto that sent the Consegna of `header`, to this Mac whose key is `ownKey`.
    ///
    /// - Throws: ``Failure/otherMachine(machine:sender:)`` first, then ``Failure/unknownSender``.
    static func sender(of header: DeliveryHeader, ownKey: KeyID, among tickets: [ReceivedTicket]) throws(Failure)
        -> ReceivedTicket {
        let known = tickets.first { $0.keyIdentifier == header.sender }
        guard header.recipient == ownKey else {
            let machine = tickets.first { $0.keyIdentifier == header.recipient }?.machine
            throw .otherMachine(machine: machine, sender: known?.person)
        }
        guard let known, known.status == .verified else { throw .unknownSender }
        return known
    }

    /// Opens the Consegna at `file` with this Mac's `key`: checks it, decrypts it and extracts it in its folder. The
    /// `.bubo` itself is never touched. The same Consegna opened again keeps the folder already there.
    ///
    /// - Throws: ``Failure``; nothing in the clear is left when the opening fails.
    func open<Key: HPKEDiffieHellmanPrivateKey>(_ file: URL, with key: Key, among tickets: [ReceivedTicket])
        throws(Failure) -> Opened where Key.PublicKey == P256.KeyAgreement.PublicKey {
        let header: DeliveryHeader
        do {
            header = try DeliveryHeader(contentsOf: file)
        } catch {
            throw .damaged(sender: nil)
        }
        let sender = try Self.sender(of: header, ownKey: KeyID(key.publicKey), among: tickets)
        guard let senderKey = try? P256.KeyAgreement.PublicKey(x963Representation: sender.publicKey) else {
            throw .unknownSender
        }
        let manager = FileManager.default
        let incoming = root.appending(path: ".in-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: incoming) }
        let archive = incoming.appending(path: "contenuto.aar")
        let content = incoming.appending(path: "contenuto", directoryHint: .isDirectory)
        do {
            try manager.createDirectory(at: content, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch {
            throw .unavailable
        }
        do {
            try DeliveryCipher.open(contentsOf: file, to: archive, with: key, from: senderKey)
        } catch .otherRecipient {
            throw .otherMachine(machine: nil, sender: sender.person)
        } catch .otherSender {
            throw .unknownSender
        } catch {
            throw .damaged(sender: sender.person)
        }
        let manifest: DeliveryManifest
        do {
            try DeliveryArchive.extract(archive, to: content)
            manifest = try JSONDecoder().decode(DeliveryManifest.self,
                                                from: Data(contentsOf: content.appending(path: DeliveryManifest.fileName)))
        } catch {
            throw .damaged(sender: sender.person)
        }
        // The id names a file: only a UUID, as the sender's Bubo writes it.
        guard UUID(uuidString: manifest.sessionID) != nil else { throw .damaged(sender: sender.person) }

        let folder = Self.folder(of: manifest.id, in: root)
        if !manager.fileExists(atPath: folder.path) {
            do {
                try manager.moveItem(at: content, to: folder)
            } catch {
                throw .unavailable
            }
        }
        return Opened(manifest: manifest, folder: folder, sender: sender)
    }

    /// The folder of the Consegna `id` in `root`.
    static func folder(of id: UUID, in root: URL) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    // MARK: Metti tra le Bozze

    /// Imports the branch of `opened` into the checkout `project` as `consegna/‹mittente›/‹nome›`, with `-2`, `-3`
    /// when the name is taken; when the base is missing, fetches from `origin` first and tries again.
    ///
    /// - Returns: The new branch; `nil` when the Consegna has none.
    /// - Throws: ``Failure/baseUnreachable(sender:branch:)``.
    @concurrent func importBranch(of opened: Opened, into project: URL) async throws(Failure) -> String? {
        let manifest = opened.manifest
        let bundle = opened.folder.appending(path: DeliveryManifest.bundleName)
        guard let ref = manifest.bundleRef, FileManager.default.fileExists(atPath: bundle.path) else { return nil }
        let unreachable = Failure.baseUnreachable(sender: manifest.person, branch: manifest.branch)
        let existing = (try? await git(["for-each-ref", "--format=%(refname:short)", "refs/heads/consegna/"],
                                       in: project)) ?? ""
        let name = Self.branchName(person: manifest.person, branch: manifest.branch ?? manifest.title,
                                   taken: Set(existing.split(separator: "\n").map(String.init)))
        let fetch = ["fetch", "--quiet", "--no-tags", bundle.path, "\(ref):refs/heads/\(name)"]
        if (try? await git(fetch, in: project)) != nil { return name }
        // The bundle lists the commits it needs; the remote may have them.
        guard (try? await git(["fetch", "--quiet", "origin"], in: project)) != nil,
              (try? await git(fetch, in: project)) != nil
        else { throw unreachable }
        return name
    }

    /// `consegna/‹mittente›/‹nome›` as a valid git branch name, with `-2`, `-3` when one of `taken` has it.
    static func branchName(person: String, branch: String, taken: Set<String>) -> String {
        // The sender's own branch, without its folders: `bubo/stampa` → `stampa`.
        let leaf = branch.split(separator: "/").last.map(String.init) ?? branch
        let base = "consegna/\(slug(person, fallback: "mittente"))/\(slug(leaf, fallback: "sessione"))"
        var name = base
        var suffix = 2
        while taken.contains(name) {
            name = "\(base)-\(suffix)"
            suffix += 1
        }
        return name
    }

    /// Lowercase letters, digits and dashes, without accents.
    private static func slug(_ text: String, fallback: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let slug = words.joined(separator: "-")
        return slug.isEmpty ? fallback : String(slug.prefix(40))
    }

    // MARK: Dove

    /// The Progetto among `projects` whose `origin` is `remote`, in any of its forms (`git@`, `https://`, `.git`).
    @concurrent func project(withRemote remote: String, among projects: [URL]) async -> URL? {
        let wanted = Self.normalized(remote: remote)
        for project in projects {
            if let url = try? await git(["remote", "get-url", "origin"], in: project),
               Self.normalized(remote: url) == wanted {
                return project
            }
        }
        return nil
    }

    /// `host/owner/repo` of a remote URL, lowercased: `git@github.com:a/b.git` and `https://github.com/a/b` match.
    static func normalized(remote: String) -> String {
        var text = remote.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let at = text.firstIndex(of: "@"), !text[..<at].contains("/") { text = String(text[text.index(after: at)...]) }
        text = text.replacing(":", with: "/")
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        return text
    }

    /// Clona: clones `remote` into a new folder inside `parent`, named after the repo.
    ///
    /// - Returns: The new checkout.
    /// - Throws: ``BranchBundler/Failure`` with what git said.
    @concurrent func clone(_ remote: String, into parent: URL) async throws -> URL {
        let name = Self.normalized(remote: remote).split(separator: "/").last.map(String.init) ?? "progetto"
        var folder = parent.appending(path: name, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appending(path: "\(name)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        try await git(["clone", "--quiet", remote, folder.path], in: parent)
        return folder
    }

    // MARK: Avvia

    /// Writes the conversation in `folder` for the worktree `worktree`, as `claude` would have written it there:
    /// `‹progetto›` becomes the worktree, files in the `claudeProjects` folder of the worktree's project key.
    ///
    /// - Returns: The transcript written.
    /// - Throws: A file error.
    @discardableResult
    static func restore(_ folder: URL, sessionID: String, for worktree: URL, in claudeProjects: URL) throws -> URL {
        let manager = FileManager.default
        let project = claudeProjects.appending(path: ProjectMemory.folderName(ofRoot: worktree.path),
                                               directoryHint: .isDirectory)
        let sessionFolder = project.appending(path: sessionID, directoryHint: .isDirectory)
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        let path = worktree.path
        // Inside a JSON string the path is escaped as JSON escapes it.
        let jsonPath = path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        let placeholder = TranscriptCleaner.projectPlaceholder

        func copy(_ source: URL, to target: URL, isJSON: Bool) throws {
            let text = try String(contentsOf: source, encoding: .utf8)
            try Data(text.replacing(placeholder, with: isJSON ? jsonPath : path).utf8).write(to: target)
        }

        let transcript = project.appending(path: "\(sessionID).jsonl")
        try copy(folder.appending(path: DeliveryManifest.transcriptName), to: transcript, isJSON: true)
        for name in [DeliveryManifest.subagentsFolder, DeliveryManifest.toolResultsFolder] {
            let source = folder.appending(path: name, directoryHint: .isDirectory)
            guard let files = try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil),
                  !files.isEmpty
            else { continue }
            let target = sessionFolder.appending(path: name, directoryHint: .isDirectory)
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            for file in files {
                let isJSON = file.pathExtension == "jsonl" || file.pathExtension == "json"
                try copy(file, to: target.appending(path: file.lastPathComponent), isJSON: isJSON)
            }
        }
        return transcript
    }

    // MARK: Scarta

    /// Scarta: deletes the content in the clear of the Consegna `id` and, in `project`, its branch unless a worktree
    /// has it checked out: git refuses to delete that one.
    @concurrent func discard(_ id: UUID, branch: String?, in project: URL?) async {
        try? FileManager.default.removeItem(at: Self.folder(of: id, in: root))
        guard let branch, let project else { return }
        _ = try? await git(["branch", "-D", branch], in: project)
    }

    @discardableResult
    private func git(_ arguments: [String], in folder: URL) async throws -> String {
        let output = try await runner.run(Self.git, ["-C", folder.path] + arguments)
        guard output.exitCode == 0 else { throw BranchBundler.Failure(message: output.standardError) }
        return output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
