import Foundation
import Testing
@testable import Bubo

/// Past conversations in the Indice, from made-up transcripts in a temporary folder: never the user's own.
@Suite(.timeLimit(.minutes(1)))
struct ConversationIndexTests {
    let claude: ClaudeFolder

    init() throws {
        claude = try ClaudeFolder()
    }

    static let saidAt = Date(timeIntervalSince1970: 1_790_846_145)

    static let turn = [
        CLIConversation.Message(id: "m1", isFromUser: true, text: "Il gatto si chiama Briciola, ricordalo.", date: saidAt),
        CLIConversation.Message(id: "m2", isFromUser: false, text: "Ricorderò il nome del gatto."),
    ]

    @Test func aMessageIsFoundWithItsConversationAuthorAndDate() async throws {
        let index = try claude.open()
        let modified = Date(timeIntervalSince1970: 1_790_900_000)
        try await index.store(Self.turn, ofConversation: "c-1", in: URL(filePath: "/Users/a/bubo"), modified: modified)

        let hits = try await index.hits(for: "Briciola", source: .conversations)
        #expect(hits == [SearchHit(path: "c-1", project: "-Users-a-bubo", source: .conversations, text: Self.turn[0].text,
                                   message: ConversationMessage(id: "m1", isFromUser: true, date: Self.saidAt))])
        // A message without a date takes the conversation's.
        #expect(try await index.hits(for: "Ricorderò").first?.message
            == ConversationMessage(id: "m2", isFromUser: false, date: modified))
        #expect(try await index.hits(for: "Briciola", project: "/Users/a/bubo").count == 1)
        #expect(try await index.hits(for: "Briciola", source: .memory).isEmpty)
        #expect(await index.modificationDate(ofConversation: "c-1") == modified)
    }

    @Test func cercaNamesTheConversationWhoWroteAndWhen() async throws {
        let index = try claude.open()
        try await index.store(Self.turn, ofConversation: "c-1", in: nil, modified: .now)

        let result = await index.toolResult(for: "Briciola", project: nil, source: .conversations)
        #expect(result.hasPrefix("### Conversazione c-1, messaggio di l'utente del \(Self.saidAt.formatted(.iso8601))"))
        #expect(result.contains("Il gatto si chiama Briciola"))
    }

    @Test func storingAgainReplacesAndForgettingRemoves() async throws {
        let index = try claude.open()
        try await index.store(Self.turn, ofConversation: "c-1", in: nil, modified: .now)
        try await index.store([CLIConversation.Message(isFromUser: true, text: "Ora parliamo di cani.")],
                              ofConversation: "c-1", in: nil, modified: .now)
        #expect(try await index.hits(for: "Briciola").isEmpty)
        #expect(try await index.hits(for: "cani").count == 1)

        try await index.forgetConversations(["c-1"])
        #expect(try await index.hits(for: "cani").isEmpty)
        #expect(await index.modificationDate(ofConversation: "c-1") == nil)
    }

    @Test func theConversationsOfAMemoryRescanStay() async throws {
        let index = try claude.open()
        try await index.store(Self.turn, ofConversation: "c-1", in: nil, modified: .now)
        await index.rescan()
        #expect(try await index.hits(for: "Briciola").count == 1)
    }

    /// A bridge played by `/bin/sh` that answers every transcript with one message saying "Briciola", and lists `c-cli`
    /// in the Cronologia CLI.
    static let bridgeScript = #"""
        while read line; do
            id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
            conversation=$(echo "$line" | sed -n 's/.*"conversation":"\([^"]*\)".*/\1/p')
            echo "$line" | grep -q '"all":true' || continue
            echo "{\"v\":3,\"type\":\"transcript\",\"id\":\"$id\",\"messages\":[{\"id\":\"m1\",\"role\":\"user\",\"text\":\"In $conversation il gatto si chiama Briciola\"}]}"
        done
        """#

    static func indexer(over index: SearchIndex) -> ConversationIndexer {
        let bridge = AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", bridgeScript],
                                 environment: ["PATH": "/usr/bin:/bin"]) { _, _, _ in "" }
        return ConversationIndexer(index: index) { bridge }
    }

    @Test func aPhraseSaidInAClosedTurnIsFoundWithCerca() async throws {
        let index = try claude.open()
        await Self.indexer(over: index).add("turn-1", in: URL(filePath: "/Users/a/bubo"))

        let result = await index.toolResult(for: "Briciola", project: nil)
        #expect(result.contains("### Conversazione turn-1"))
        #expect(result.contains("In turn-1 il gatto si chiama Briciola"))
    }

    @Test func catchingUpAddsOnlyWhatIsMissingOrChanged() async throws {
        let index = try claude.open()
        let old = Date(timeIntervalSince1970: 1_000)
        try await index.store([], ofConversation: "turn-kept", in: nil, modified: old)
        try await index.store([], ofConversation: "c-same", in: nil, modified: old)
        let history = [
            CLIConversation(id: "c-same", title: "Uguale", folder: nil, branch: nil, lastModified: old),
            CLIConversation(id: "c-new", title: "Nuova", folder: URL(filePath: "/Users/a/app"), branch: nil,
                            lastModified: Date(timeIntervalSince1970: 2_000)),
        ]
        await Self.indexer(over: index).catchUp(turns: [("turn-kept", URL(filePath: "/p")), ("turn-lost", URL(filePath: "/p"))],
                                                history: history)

        let found = Set(try await index.hits(for: "Briciola").map(\.path))
        #expect(found == ["turn-lost", "c-new"])
        #expect(await index.modificationDate(ofConversation: "c-new") == Date(timeIntervalSince1970: 2_000))
    }

    /// The transcripts' format is internal to `claude`: the Indice reads conversations only through the bridge's SDK.
    @Test func theIndiceNeverReadsTranscriptFiles() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Bubo/Index")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        #expect(files.contains("ConversationIndexer.swift"))
        for file in files {
            let source = try String(contentsOf: folder.appending(path: file), encoding: .utf8)
            #expect(!source.localizedCaseInsensitiveContains("jsonl"), "\(file) mentions the transcripts' files")
        }
    }
}
