import CryptoKit
import DeliveryKit
import Foundation
import SQLite3
import Testing
@testable import Bubo

/// `DeliveryBuilder` on the fake Sessione of the corpus, read from a copy of the conversations made like the agent
/// bridge's, and sealed with software keys.
struct DeliveryBuilderTests {
    let corpus = DeliveryCorpus.shared
    let folder = URL.temporaryDirectory.appending(path: "DeliveryBuilderTests-\(UUID().uuidString)",
                                                  directoryHint: .isDirectory)
    let conversation = "6f1e2d3c-4b5a-4968-8776-655443322110"

    /// Bubo's copy with the corpus's transcript and subagent, and `~/.claude/projects` with its tool results.
    func makeSource() throws -> DeliveryBuilder.Source {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = try DeliveryCorpus.session()
        let mirror = folder.appending(path: "Conversazioni.sqlite")
        var entries = session.transcript.split(separator: "\n").map { ("", String($0)) }
        entries += try #require(session.subagents["agent-a1.jsonl"]).split(separator: "\n")
            .map { ("subagents/agent-a1", String($0)) }
        var metadata = try JSONValue.decoding(line: try #require(session.subagentMetadata["agent-a1.meta.json"]))
        if case var .object(fields) = metadata {
            fields["type"] = .string("agent_metadata")
            metadata = .object(fields)
        }
        entries.append(("subagents/agent-a1", try metadata.encodedLine()))
        try write(entries, to: mirror)

        let projects = folder.appending(path: "projects", directoryHint: .isDirectory)
        let results = projects.appending(path: ProjectMemory.folderName(ofRoot: corpus.mittente.worktree))
            .appending(path: conversation).appending(path: "tool-results", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        for (name, text) in session.toolResults { try Data(text.utf8).write(to: results.appending(path: name)) }

        return DeliveryBuilder.Source(title: "Stampa", conversationID: conversation,
                                      worktree: URL(filePath: corpus.mittente.worktree), branch: nil, base: nil,
                                      home: corpus.mittente.home, mirror: mirror, claudeProjects: projects)
    }

    /// The `entries` table of the agent bridge's copy, with `(subpath, entry)` rows.
    func write(_ entries: [(String, String)], to database: URL) throws {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        try #require(sqlite3_open(database.path, &connection) == SQLITE_OK)
        try #require(sqlite3_exec(connection, """
            CREATE TABLE entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, project TEXT NOT NULL, session TEXT NOT NULL,
            subpath TEXT NOT NULL DEFAULT '', uuid TEXT, entry TEXT NOT NULL, mtime INTEGER NOT NULL)
            """, nil, nil, nil) == SQLITE_OK)
        for (subpath, entry) in entries {
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(connection, "INSERT INTO entries (project, session, subpath, entry, mtime) VALUES ('p', ?, ?, ?, 0)", -1, &statement, nil) == SQLITE_OK)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, conversation, -1, transient)
            sqlite3_bind_text(statement, 2, subpath, -1, transient)
            sqlite3_bind_text(statement, 3, entry, -1, transient)
            try #require(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }

    func builder() -> DeliveryBuilder {
        var builder = DeliveryBuilder()
        builder.temporaryFolder = folder.appending(path: "Consegne", directoryHint: .isDirectory)
        return builder
    }

    @Test func theMirroredSessionHasItsSubagentAndToolResults() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try makeSource()
        let toolResults = source.claudeProjects.appending(path: ProjectMemory.folderName(ofRoot: source.worktree.path))
            .appending(path: conversation).appending(path: "tool-results")

        let files = try #require(try SessionFiles.mirrored(conversation, in: source.mirror, toolResultsFolder: toolResults))
        let corpusFiles = try DeliveryCorpus.session()

        #expect(files.transcript.split(separator: "\n") == corpusFiles.transcript.split(separator: "\n"))
        #expect(files.subagents.mapValues { $0.split(separator: "\n") }
            == corpusFiles.subagents.mapValues { $0.split(separator: "\n") })
        #expect(files.subagentMetadata.keys.sorted() == ["agent-a1.meta.json"])
        #expect(files.toolResults == corpusFiles.toolResults)
    }

    @Test func thePreviewFindsTheSecretsAndTheIdentity() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let preview = try await builder().prepare(try makeSource(), person: "Ada")

        #expect(Set(preview.sender.identity).isSuperset(of: [corpus.mittente.email, corpus.mittente.organizzazione,
                                                             corpus.mittente.idOrganizzazione]))
        for secret in corpus.secrets.values {
            #expect(preview.findings.contains { $0.value == secret })
        }
        #expect(preview.branch == nil)
        #expect(preview.cleaned.messageCount > 0)
        #expect(preview.claudeVersion == "2.1.287")
        #expect(preview.lines.allSatisfy { line in
            line.segments.allSatisfy { segment in
                guard case let .plain(text) = segment else { return true }
                return !corpus.secrets.values.contains { text.contains($0) }
            }
        })
    }

    @Test func theBuboOpensForTheRecipientWithoutTheSecretsTakenOut() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let builder = builder()
        let preview = try await builder.prepare(try makeSource(), person: "Ada")
        let recipient = P256.KeyAgreement.PrivateKey()
        let sender = P256.KeyAgreement.PrivateKey()
        let removed = Set(preview.findings.map(\.value))

        let file = try await builder.build(preview, removing: removed, person: "Ada", machine: "MacBook",
                                           for: recipient.publicKey, sealedBy: sender)

        #expect(file.pathExtension == "bubo")
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            == [file.lastPathComponent])
        let archive = folder.appending(path: "aperto.aar")
        let header = try DeliveryCipher.open(contentsOf: file, to: archive, with: recipient, from: sender.publicKey)
        #expect(header.kind == .consegna)
        let content = folder.appending(path: "aperto", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try DeliveryArchive.extract(archive, to: content)

        let manifest = try JSONDecoder().decode(DeliveryManifest.self,
                                                from: Data(contentsOf: content.appending(path: "manifest.json")))
        #expect(manifest.id == preview.id)
        #expect(manifest.counts.secretsRemoved == removed.count)
        #expect(manifest.bundleRef == nil)
        let texts = try [
            "transcript.jsonl", "subagents/agent-a1.jsonl", "subagents/agent-a1.meta.json", "tool-results/toolu_big.txt",
        ].map { try String(contentsOf: content.appending(path: $0), encoding: .utf8) }
        for text in texts {
            for secret in removed { #expect(!text.contains(secret)) }
            #expect(!text.contains(corpus.mittente.email))
            #expect(!text.contains(corpus.mittente.worktree))
        }
        #expect(texts[0].contains(manifest.sessionID))
    }
}
