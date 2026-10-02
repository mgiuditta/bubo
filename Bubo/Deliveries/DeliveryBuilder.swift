import CryptoKit
import DeliveryKit
import Foundation

/// The sender's side of a Consegna (spec 24, Mittente): reads the Sessione from Bubo's copy, cleans it, scans it and
/// bundles its branch for the foglio; at Condividi… cleans it again with the secrets decided Togli, archives it,
/// encrypts it for the chosen Macchina and writes the `.bubo` in a temporary folder.
nonisolated struct DeliveryBuilder: Sendable {
    /// The Sessione to deliver, and where its files are.
    struct Source: Sendable {
        var title: String
        /// The agent's conversation that holds the whole Sessione: its latest turn.
        var conversationID: String
        /// The folder `claude` ran in.
        var worktree: URL
        /// The Sessione's branch; `nil` outside git.
        var branch: String?
        /// The commit the Sessione started from.
        var base: String?
        /// The sender's home folder, which becomes `‹progetto›` too.
        var home: String
        /// Bubo's copy of the conversations (ADR 0006).
        var mirror: URL
        /// `~/.claude/projects`, for the tool results the copy does not hold.
        var claudeProjects: URL
    }

    /// What the foglio shows, ready to become a `.bubo`.
    struct Preview: Sendable {
        let id: UUID
        let title: String
        /// The Sessione as `claude` wrote it: cleaned again at Condividi… with the secrets decided Togli.
        let files: SessionFiles
        let sender: TranscriptCleaner.Sender
        let newSessionID: String
        /// The Sessione cleaned with no secret taken out yet: the counts and the Conversazione ripulita.
        let cleaned: TranscriptCleaner.Result
        let lines: [DeliveryPreviewLine]
        let findings: [SecretScanner.Finding]
        /// The findings that are also in the uncommitted changes, which Togli does not reach.
        let findingsInBranch: Set<SecretScanner.Finding.ID>
        /// The branch; `nil` outside git.
        let branch: BranchBundler.Snapshot?
        /// The bundle of the branch, in the preparation folder; `nil` without a branch or with nothing new.
        let bundle: URL?
        let bundleRef: String?
        let claudeVersion: String?
        /// The folder of this preparation: deleted with ``discard()``.
        let folder: URL

        /// The size of what goes out before compression, in bytes: what the foglio shows and checks against 100 MB.
        var estimatedSize: Int {
            let texts = cleaned.files.transcript.utf8.count
                + cleaned.files.subagents.values.reduce(0) { $0 + $1.utf8.count }
                + cleaned.files.subagentMetadata.values.reduce(0) { $0 + $1.utf8.count }
                + cleaned.files.toolResults.values.reduce(0) { $0 + $1.utf8.count }
            let bundleSize = bundle.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
            return texts + bundleSize
        }

        /// Deletes the preparation folder and the bundle in it.
        func discard() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Why the Consegna cannot be prepared.
    enum Failure: Error, Equatable {
        /// Bubo's copy has no line of the Sessione.
        case conversationMissing
        /// Bubo's copy does not open.
        case mirrorUnreadable
        /// A line Bubo does not know how to clean.
        case cleaning(TranscriptCleaner.Failure)
        /// git failed on the branch.
        case branch(String)
        /// The rules of the scanner are missing from the app.
        case scannerMissing
    }

    /// The size past which Messaggi may not send the file (spec 24, Peso).
    static let largeSize = 100_000_000

    /// The folder of the Consegne being prepared and written; each has a subfolder named by its id.
    var temporaryFolder = FileManager.default.temporaryDirectory.appending(path: "Consegne", directoryHint: .isDirectory)
    var bundler = BranchBundler()
    var scanner = SecretScanner.bundled

    /// Reads, cleans, scans and bundles the Sessione of `source`, for the foglio; `person` signs the commit of the
    /// uncommitted changes.
    ///
    /// - Throws: ``Failure``.
    @concurrent func prepare(_ source: Source, person: String) async throws(Failure) -> Preview {
        guard let scanner else { throw .scannerMissing }
        let toolResults = source.claudeProjects
            .appending(path: ProjectMemory.folderName(ofRoot: source.worktree.path), directoryHint: .isDirectory)
            .appending(path: source.conversationID, directoryHint: .isDirectory)
            .appending(path: "tool-results", directoryHint: .isDirectory)
        let mirrored: SessionFiles?
        do {
            mirrored = try SessionFiles.mirrored(source.conversationID, in: source.mirror, toolResultsFolder: toolResults)
        } catch {
            throw .mirrorUnreadable
        }
        guard let files = mirrored else { throw .conversationMissing }

        let sender = TranscriptCleaner.Sender(worktree: source.worktree.path, home: source.home,
                                              identity: Self.identity(in: files))
        let newSessionID = UUID().uuidString.lowercased()
        let cleaned: TranscriptCleaner.Result
        do {
            cleaned = try TranscriptCleaner(sender: sender, newSessionID: newSessionID).cleaning(files)
        } catch {
            throw .cleaning(error)
        }

        let id = UUID()
        let folder = temporaryFolder.appending(path: id.uuidString, directoryHint: .isDirectory)
        var snapshot: BranchBundler.Snapshot?
        var bundle: URL?
        var bundleRef: String?
        if let branch = source.branch {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let taken = try await bundler.snapshot(of: source.worktree, branch: branch, fallbackBase: source.base)
                let file = folder.appending(path: DeliveryManifest.bundleName)
                bundleRef = try await bundler.bundle(taken, in: source.worktree, sender: person, to: file)
                bundle = bundleRef == nil ? nil : file
                snapshot = taken
            } catch let failure as BranchBundler.Failure {
                try? FileManager.default.removeItem(at: folder)
                throw .branch(failure.message)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw .branch(error.localizedDescription)
            }
        }

        // The cleaned files, so a path or the email is not reported as a secret; the uncommitted changes too.
        var documents = SecretScanner.documents(of: cleaned.files)
        let diffLocation = SecretScanner.Location(file: DeliveryManifest.bundleName, line: 1)
        if let diff = snapshot?.uncommittedDiff, !diff.isEmpty {
            documents.append(SecretScanner.Document(text: diff, location: diffLocation))
        }
        let findings = scanner.scan(documents, envValues: SecretScanner.envValues(in: cleaned.files))
        let inBranch = Set(findings.filter { $0.locations.contains { $0.file == DeliveryManifest.bundleName } }.map(\.id))

        return Preview(
            id: id, title: source.title, files: files, sender: sender, newSessionID: newSessionID, cleaned: cleaned,
            lines: DeliveryPreviewLine.lines(of: cleaned.files.transcript, findings: findings),
            findings: findings, findingsInBranch: inBranch, branch: snapshot, bundle: bundle, bundleRef: bundleRef,
            claudeVersion: Self.claudeVersion(in: files.transcript), folder: folder
        )
    }

    /// Writes the `.bubo` of `preview` for `recipient`, sealed by `senderKey`, with `removedSecrets` taken out.
    ///
    /// - Returns: The file, named after the Sessione, alone in a new folder inside the preparation folder.
    /// - Throws: ``TranscriptCleaner/Failure``, a file error, or an error of the archive or the encryption.
    @concurrent func build<Key: HPKEDiffieHellmanPrivateKey & Sendable>(
        _ preview: Preview, removing removedSecrets: Set<String>, person: String, machine: String,
        for recipient: P256.KeyAgreement.PublicKey, sealedBy senderKey: Key
    ) async throws -> URL where Key.PublicKey == P256.KeyAgreement.PublicKey {
        let cleaned = try TranscriptCleaner(sender: preview.sender, newSessionID: preview.newSessionID,
                                            removedSecrets: removedSecrets).cleaning(preview.files)
        let content = preview.folder.appending(path: "contenuto", directoryHint: .isDirectory)
        let archive = preview.folder.appending(path: "contenuto.aar")
        defer {
            try? FileManager.default.removeItem(at: content)
            try? FileManager.default.removeItem(at: archive)
        }
        try write(cleaned, of: preview, removing: removedSecrets, person: person, machine: machine, into: content)
        try DeliveryArchive.archive(content, to: archive)

        // A folder of its own, which the Condividi deletes when it closes; the preparation stays for another try.
        let output = preview.folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let name = preview.title.replacing("/", with: "-").replacing(":", with: "-")
        let file = output.appending(path: name.isEmpty ? "Consegna" : name).appendingPathExtension(for: .buboFile)
        try DeliveryCipher.seal(contentsOf: archive, to: file, for: recipient, from: senderKey)
        return file
    }

    private func write(_ cleaned: TranscriptCleaner.Result, of preview: Preview, removing removedSecrets: Set<String>,
                       person: String, machine: String, into content: URL) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: content)
        try manager.createDirectory(at: content, withIntermediateDirectories: true)
        let manifest = DeliveryManifest(
            id: preview.id, title: preview.title, person: person, machine: machine, remote: preview.branch?.remote,
            baseCommit: preview.bundle == nil ? nil : preview.branch?.base, branch: preview.branch?.branch,
            bundleRef: preview.bundleRef, sessionID: preview.newSessionID, claudeVersion: preview.claudeVersion,
            counts: DeliveryManifest.Counts(
                messages: cleaned.messageCount, subagents: cleaned.files.subagents.count,
                reasoningBlocksRemoved: cleaned.removed[.reasoning] ?? 0, secretsRemoved: removedSecrets.count
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: content.appending(path: DeliveryManifest.fileName))
        try Data(cleaned.files.transcript.utf8).write(to: content.appending(path: DeliveryManifest.transcriptName))
        if !cleaned.files.subagents.isEmpty || !cleaned.files.subagentMetadata.isEmpty {
            let folder = content.appending(path: DeliveryManifest.subagentsFolder, directoryHint: .isDirectory)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in cleaned.files.subagents.merging(cleaned.files.subagentMetadata, uniquingKeysWith: { $1 }) {
                try Data(text.utf8).write(to: folder.appending(path: Self.safeName(name)))
            }
        }
        if !cleaned.files.toolResults.isEmpty {
            let folder = content.appending(path: DeliveryManifest.toolResultsFolder, directoryHint: .isDirectory)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in cleaned.files.toolResults {
                try Data(text.utf8).write(to: folder.appending(path: Self.safeName(name)))
            }
        }
        if let bundle = preview.bundle {
            try manager.copyItem(at: bundle, to: content.appending(path: DeliveryManifest.bundleName))
        }
    }

    /// A file name with no folder in it.
    private static func safeName(_ name: String) -> String {
        name.replacing("/", with: "-")
    }

    /// The account's email, organization and their ids, as the Sessione's `session_context` and `credential_org`
    /// lines carry them: they become `‹tolto›` wherever else they appear.
    static func identity(in files: SessionFiles) -> [String] {
        var values: Set<String> = []
        for (_, content) in files.jsonlFiles {
            for line in content.split(separator: "\n") where line.contains("\"attachment\"") {
                guard let value = try? JSONValue.decoding(line: line), value["type"]?.string == "attachment",
                      let attachment = value["attachment"],
                      ["session_context", "credential_org"].contains(attachment["type"]?.string ?? "")
                else { continue }
                for case let (key, .string(text)) in Self.fields(of: attachment) where key != "type" && text.count >= 4 {
                    values.insert(text)
                }
            }
        }
        return values.sorted()
    }

    private static func fields(of value: JSONValue) -> [(String, JSONValue)] {
        guard case let .object(fields) = value else { return [] }
        return fields.map { ($0.key, $0.value) }
    }

    /// The `version` of `claude` on the transcript's last line that has one.
    static func claudeVersion(in transcript: String) -> String? {
        for line in transcript.split(separator: "\n").reversed() where line.contains("\"version\"") {
            if let version = (try? JSONValue.decoding(line: line))?["version"]?.string { return version }
        }
        return nil
    }
}
