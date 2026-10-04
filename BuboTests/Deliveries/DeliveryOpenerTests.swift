import CryptoKit
import DeliveryKit
import Foundation
import Testing
@testable import Bubo

/// `DeliveryOpener` on Consegne made here with software keys, fake content and fake repos of the real git: each
/// error with a file built for it, nothing in the clear before the checks, the branch, the restore and Scarta.
struct DeliveryOpenerTests {
    let base: URL
    let opener: DeliveryOpener
    let ownKey = P256.KeyAgreement.PrivateKey()
    let senderKey = P256.KeyAgreement.PrivateKey()
    let sessionID = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "DeliveryOpenerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var opener = DeliveryOpener()
        opener.root = base.appending(path: "Consegne", directoryHint: .isDirectory)
        self.opener = opener
    }

    /// The Biglietto of the sender, verified unless `status` says otherwise.
    func senderTicket(_ status: ReceivedTicket.Status = .verified) -> ReceivedTicket {
        ReceivedTicket(id: UUID(), person: "Ada", machine: "MacBook di Ada",
                       publicKey: senderKey.publicKey.x963Representation, status: status, verifiedAt: .now)
    }

    func manifest(id: UUID = UUID(), bundleRef: String? = nil, branch: String? = nil, remote: String? = nil)
        -> DeliveryManifest {
        DeliveryManifest(id: id, title: "Stampa", person: "Ada", machine: "MacBook di Ada", remote: remote,
                         baseCommit: nil, branch: branch, bundleRef: bundleRef, sessionID: sessionID,
                         claudeVersion: "2.1.287",
                         counts: DeliveryManifest.Counts(messages: 2, subagents: 1, reasoningBlocksRemoved: 1,
                                                         secretsRemoved: 0))
    }

    /// A `.bubo` with `manifest`, a transcript and a subagent written with `‹progetto›`, and `bundle` if given,
    /// sealed for `recipient` by `sender`; `padding` bytes of tool results make it bigger.
    func makeDelivery(_ manifest: DeliveryManifest, bundle: URL? = nil, padding: Int = 0,
                      for recipient: P256.KeyAgreement.PublicKey? = nil,
                      from sender: P256.KeyAgreement.PrivateKey? = nil) throws -> URL {
        let folder = base.appending(path: "uscita-\(UUID().uuidString)", directoryHint: .isDirectory)
        let content = folder.appending(path: "contenuto", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content.appending(path: "subagents"), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: content.appending(path: DeliveryManifest.fileName))
        let line = #"{"type":"user","cwd":"‹progetto›","sessionId":"\#(sessionID)","message":{"content":"‹progetto›/a.swift"}}"#
        try Data((line + "\n").utf8).write(to: content.appending(path: DeliveryManifest.transcriptName))
        try Data((line + "\n").utf8).write(to: content.appending(path: "subagents/agent-a1.jsonl"))
        try Data(#"{"agentType":"Explore","cwd":"‹progetto›"}"#.utf8)
            .write(to: content.appending(path: "subagents/agent-a1.meta.json"))
        if padding > 0 {
            try FileManager.default.createDirectory(at: content.appending(path: "tool-results"),
                                                    withIntermediateDirectories: true)
            let bytes = (0..<padding).map { _ in UInt8.random(in: 0x21...0x7E) }
            try Data(bytes).write(to: content.appending(path: "tool-results/toolu_big.txt"))
        }
        if let bundle { try FileManager.default.copyItem(at: bundle, to: content.appending(path: "ramo.bundle")) }
        let archive = folder.appending(path: "contenuto.aar")
        try DeliveryArchive.archive(content, to: archive)
        let file = folder.appending(path: "Stampa.bubo")
        try DeliveryCipher.seal(contentsOf: archive, to: file, for: recipient ?? ownKey.publicKey,
                                from: sender ?? senderKey)
        return file
    }

    /// The folders in the clear the opener left: none before the checks pass.
    func clearFolders() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: opener.root.path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    // MARK: Errors

    @Test func aConsegnaForAnotherMacchinaSaysWhichOne() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let other = P256.KeyAgreement.PrivateKey()
        let file = try makeDelivery(manifest(), for: other.publicKey)
        let otherTicket = ReceivedTicket(id: UUID(), person: "Bea", machine: "iMac di Bea",
                                         publicKey: other.publicKey.x963Representation, status: .verified,
                                         verifiedAt: .now)

        #expect(throws: DeliveryOpener.Failure.otherMachine(machine: "iMac di Bea", sender: "Ada")) {
            try opener.open(file, with: ownKey, among: [senderTicket(), otherTicket])
        }
        #expect(clearFolders().isEmpty)
    }

    @Test func anUnknownOrChangedSenderDoesNotOpen() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try makeDelivery(manifest())

        #expect(throws: DeliveryOpener.Failure.unknownSender) { try opener.open(file, with: ownKey, among: []) }
        #expect(throws: DeliveryOpener.Failure.unknownSender) {
            try opener.open(file, with: ownKey, among: [senderTicket(.keyChanged)])
        }
        #expect(clearFolders().isEmpty)
    }

    @Test func aFileChangedByOneByteIsDamaged() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try makeDelivery(manifest())
        var data = try Data(contentsOf: file)
        data[data.count - 20] ^= 0x01
        try data.write(to: file)

        #expect(throws: DeliveryOpener.Failure.damaged(sender: "Ada")) {
            try opener.open(file, with: ownKey, among: [senderTicket()])
        }
        #expect(clearFolders().isEmpty)
    }

    @Test func aConsegnaMadeByAnotherKeyThanItsHeaderSaysIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        // Sealed by an impostor, then the header rewritten with the sender's key id.
        let impostor = P256.KeyAgreement.PrivateKey()
        let file = try makeDelivery(manifest(), from: impostor)
        var data = try Data(contentsOf: file)
        data.replaceSubrange(14..<22, with: KeyID(senderKey.publicKey).bytes)
        try data.write(to: file)

        #expect(throws: DeliveryOpener.Failure.damaged(sender: "Ada")) {
            try opener.open(file, with: ownKey, among: [senderTicket()])
        }
        #expect(clearFolders().isEmpty)
    }

    @Test(arguments: [
        DeliveryOpener.Failure.otherMachine(machine: "iMac di Bea", sender: "Ada"),
        .otherMachine(machine: nil, sender: nil), .damaged(sender: "Ada"), .damaged(sender: nil), .unknownSender,
        .baseUnreachable(sender: "Ada", branch: "bubo/stampa"), .unavailable,
    ])
    func everyErrorHasItsText(_ failure: DeliveryOpener.Failure) {
        let message = DeliveryErrorSheet.message(for: failure, machine: "Mac di Ciro")

        #expect(!message.isEmpty)
        if case .otherMachine = failure { #expect(message.contains("Mac di Ciro")) }
        if case let .otherMachine(machine?, _) = failure { #expect(message.contains(machine)) }
        if case let .baseUnreachable(sender, branch?) = failure {
            #expect(message.contains(sender) && message.contains(branch))
        }
    }

    // MARK: Opening

    @Test func aVerifiedConsegnaOpensInItsFolderOnce() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID()
        let file = try makeDelivery(manifest(id: id))

        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])
        let again = try opener.open(file, with: ownKey, among: [senderTicket()])

        #expect(opened.manifest.id == id)
        #expect(opened.sender.person == "Ada")
        #expect(opened.folder == DeliveryOpener.folder(of: id, in: opener.root))
        #expect(again.folder == opened.folder)
        #expect(clearFolders() == [id.uuidString])
        #expect(FileManager.default.fileExists(atPath: opened.folder.appending(path: "transcript.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aConsegnaOfFiveMegabytesWithItsBranchOpensInLessThanTenSeconds() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (sender, receiver, _) = try makeRepos(receiverHasBase: true)
        let bundle = try makeBundle(in: sender)
        let file = try makeDelivery(manifest(bundleRef: "refs/heads/bubo/stampa", branch: "bubo/stampa"),
                                    bundle: bundle, padding: 5_000_000)

        let start = ContinuousClock.now
        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])
        let branch = try await opener.importBranch(of: opened, into: receiver)
        let elapsed = ContinuousClock.now - start

        #expect(branch == "consegna/ada/stampa")
        #expect(elapsed < .seconds(10))
    }

    // MARK: Branch

    /// The sender's repo with `main` and `bubo/stampa` one commit ahead; the receiver's clone of `main`, or an empty
    /// repo whose `origin` is the sender's when `receiverHasBase` is false.
    func makeRepos(receiverHasBase: Bool) throws -> (sender: URL, receiver: URL, base: String) {
        let sender = base.appending(path: "mittente", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sender, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main", in: sender)
        try Data("ciao\n".utf8).write(to: sender.appending(path: "README.md"))
        try git("add", "-A", in: sender)
        try git("commit", "-q", "-m", "Primo", in: sender)
        let baseCommit = try git("rev-parse", "HEAD", in: sender).trimmingCharacters(in: .newlines)
        try git("switch", "-q", "-c", "bubo/stampa", in: sender)
        try Data("print(1)\n".utf8).write(to: sender.appending(path: "stampa.swift"))
        try git("add", "-A", in: sender)
        try git("commit", "-q", "-m", "Stampa", in: sender)
        try git("switch", "-q", "main", in: sender)

        let receiver = base.appending(path: "destinatario", directoryHint: .isDirectory)
        if receiverHasBase {
            try git("clone", "-q", "--single-branch", "-b", "main", sender.path, receiver.path, in: base)
        } else {
            try FileManager.default.createDirectory(at: receiver, withIntermediateDirectories: true)
            try git("init", "-q", "-b", "main", in: receiver)
            try git("remote", "add", "origin", sender.path, in: receiver)
        }
        return (sender, receiver, baseCommit)
    }

    /// The bundle of `bubo/stampa` after `main`, as the sender's Bubo makes it.
    func makeBundle(in sender: URL) throws -> URL {
        let bundle = base.appending(path: "ramo-\(UUID().uuidString).bundle")
        try git("bundle", "create", "-q", bundle.path, "bubo/stampa", "^main", in: sender)
        return bundle
    }

    @Test func theBranchArrivesWithASuffixWhenTheNameIsTaken() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (sender, receiver, _) = try makeRepos(receiverHasBase: true)
        let file = try makeDelivery(manifest(bundleRef: "refs/heads/bubo/stampa", branch: "bubo/stampa"),
                                    bundle: try makeBundle(in: sender))
        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])

        let first = try await opener.importBranch(of: opened, into: receiver)
        let second = try await opener.importBranch(of: opened, into: receiver)

        #expect(first == "consegna/ada/stampa")
        #expect(second == "consegna/ada/stampa-2")
        #expect(try git("log", "-1", "--format=%s", "consegna/ada/stampa", in: receiver).contains("Stampa"))
    }

    @Test func aMissingBaseIsFetchedFromTheRemote() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (sender, receiver, _) = try makeRepos(receiverHasBase: false)
        let file = try makeDelivery(manifest(bundleRef: "refs/heads/bubo/stampa", branch: "bubo/stampa"),
                                    bundle: try makeBundle(in: sender))
        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])

        #expect(try await opener.importBranch(of: opened, into: receiver) == "consegna/ada/stampa")
    }

    @Test func aBaseNobodyHasMakesTheBranchUnreachable() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (sender, receiver, _) = try makeRepos(receiverHasBase: false)
        try git("remote", "remove", "origin", in: receiver)
        let file = try makeDelivery(manifest(bundleRef: "refs/heads/bubo/stampa", branch: "bubo/stampa"),
                                    bundle: try makeBundle(in: sender))
        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])

        await #expect(throws: DeliveryOpener.Failure.baseUnreachable(sender: "Ada", branch: "bubo/stampa")) {
            try await opener.importBranch(of: opened, into: receiver)
        }
    }

    @Test func aConsegnaWithoutBranchImportsNothing() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let opened = try opener.open(try makeDelivery(manifest()), with: ownKey, among: [senderTicket()])

        #expect(try await opener.importBranch(of: opened, into: base) == nil)
    }

    @Test(arguments: [
        ("Ada Lovelace", "bubo/pagina-prezzi", Set<String>(), "consegna/ada-lovelace/pagina-prezzi"),
        ("Nicolò", "Refactor del router!", [], "consegna/nicolo/refactor-del-router"),
        ("", "", [], "consegna/mittente/sessione"),
        ("Ada", "stampa", ["consegna/ada/stampa", "consegna/ada/stampa-2"], "consegna/ada/stampa-3"),
    ] as [(String, String, Set<String>, String)])
    func theBranchNameIsAValidSlug(person: String, branch: String, taken: Set<String>, expected: String) {
        #expect(DeliveryOpener.branchName(person: person, branch: branch, taken: taken) == expected)
    }

    @Test func theSameRemoteMatchesInEveryForm() {
        let forms = ["git@github.com:mgiuditta/bubo.git", "https://github.com/mgiuditta/bubo",
                     "https://github.com/mgiuditta/Bubo.git/", "ssh://git@github.com/mgiuditta/bubo.git"]

        #expect(Set(forms.map(DeliveryOpener.normalized(remote:))) == ["github.com/mgiuditta/bubo"])
        #expect(DeliveryOpener.normalized(remote: "git@github.com:altri/bubo.git") != "github.com/mgiuditta/bubo")
    }

    @Test func theProjectWithTheSameRemoteIsFound() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (_, receiver, _) = try makeRepos(receiverHasBase: false)
        try git("remote", "set-url", "origin", "git@github.com:mgiuditta/bubo.git", in: receiver)

        #expect(await opener.project(withRemote: "https://github.com/mgiuditta/bubo", among: [base, receiver])
            == receiver)
        #expect(await opener.project(withRemote: "https://github.com/altri/bubo", among: [receiver]) == nil)
    }

    // MARK: Avvia and Scarta

    @Test func theConversationIsWrittenForTheReceiversWorktree() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let opened = try opener.open(try makeDelivery(manifest(), padding: 10), with: ownKey, among: [senderTicket()])
        let worktree = URL(filePath: "/Users/bea/Worktrees/bubo/consegna-ada-stampa", directoryHint: .isDirectory)
        let projects = base.appending(path: "projects", directoryHint: .isDirectory)

        let transcript = try DeliveryOpener.restore(opened.folder, sessionID: sessionID, for: worktree, in: projects)

        let folder = projects.appending(path: ProjectMemory.folderName(ofRoot: worktree.path))
        #expect(transcript == folder.appending(path: "\(sessionID).jsonl"))
        let texts = try [
            "\(sessionID).jsonl", "\(sessionID)/subagents/agent-a1.jsonl", "\(sessionID)/subagents/agent-a1.meta.json",
        ].map { try String(contentsOf: folder.appending(path: $0), encoding: .utf8) }
        for text in texts {
            #expect(!text.contains(TranscriptCleaner.projectPlaceholder))
            #expect(text.contains(worktree.path))
            #expect((try? JSONSerialization.jsonObject(with: Data(text.split(separator: "\n")[0].utf8))) != nil)
        }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(sessionID)/tool-results/toolu_big.txt").path))
    }

    @Test func scartaDeletesTheContentAndTheBranchWithoutAWorktree() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (sender, receiver, _) = try makeRepos(receiverHasBase: true)
        let id = UUID()
        let file = try makeDelivery(manifest(id: id, bundleRef: "refs/heads/bubo/stampa", branch: "bubo/stampa"),
                                    bundle: try makeBundle(in: sender))
        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])
        let branch = try await opener.importBranch(of: opened, into: receiver)

        await opener.discard(id, branch: branch, in: receiver)

        #expect(clearFolders().isEmpty)
        #expect(try git("branch", "--list", "consegna/*", in: receiver).isEmpty)
    }

    @Test func scartaKeepsABranchAWorktreeHas() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (sender, receiver, _) = try makeRepos(receiverHasBase: true)
        let file = try makeDelivery(manifest(bundleRef: "refs/heads/bubo/stampa", branch: "bubo/stampa"),
                                    bundle: try makeBundle(in: sender))
        let opened = try opener.open(file, with: ownKey, among: [senderTicket()])
        let branch = try #require(try await opener.importBranch(of: opened, into: receiver))
        try git("worktree", "add", "-q", base.appending(path: "wt").path, branch, in: receiver)

        await opener.discard(opened.manifest.id, branch: branch, in: receiver)

        #expect(try git("branch", "--list", branch, in: receiver).contains(branch))
    }

    @Test(arguments: [
        ("2.1.290", "2.1.287", true), ("2.1.287", "2.1.287", false), ("2.1.280", "2.2.0", false),
        (nil, "2.1.287", false), ("2.1.290", nil, false),
    ] as [(String?, String?, Bool)])
    func anOlderClaudeAsksToUpdate(sender: String?, installed: String?, expected: Bool) {
        #expect(DraftDelivery.needsClaudeUpdate(senderVersion: sender, installed: installed) == expected)
    }

    @Test func aDraftSavedBeforeConsegneStillDecodes() throws {
        let draft = Draft(title: "Esporta", text: "", project: URL(filePath: "/tmp"))
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object["delivery"] = nil

        let decoded = try JSONDecoder().decode(Draft.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.delivery == nil)
    }

    @discardableResult
    func git(_ arguments: String..., in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        process.environment = ["GIT_AUTHOR_NAME": "Bubo", "GIT_AUTHOR_EMAIL": "bubo@example.com",
                               "GIT_COMMITTER_NAME": "Bubo", "GIT_COMMITTER_EMAIL": "bubo@example.com",
                               "HOME": base.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
        let output = Pipe()
        process.standardOutput = output
        let error = Pipe()
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")): \(message)")
        return String(decoding: data, as: UTF8.self)
    }
}
