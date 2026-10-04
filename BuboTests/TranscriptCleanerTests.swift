import Foundation
import Testing
@testable import Bubo

struct TranscriptCleanerTests {
    let corpus = DeliveryCorpus.shared
    let newSessionID = "11111111-2222-4333-8444-555555555555"

    func cleaned(removing secrets: Set<String> = []) throws -> TranscriptCleaner.Result {
        try TranscriptCleaner(sender: corpus.sender, newSessionID: newSessionID, removedSecrets: secrets)
            .cleaning(DeliveryCorpus.session())
    }

    /// The JSON lines of a cleaned JSONL file, by `uuid`.
    func lines(_ jsonl: String) throws -> [String: JSONValue] {
        var lines: [String: JSONValue] = [:]
        for line in jsonl.split(separator: "\n") {
            let value = try JSONValue.decoding(line: line)
            if let uuid = value["uuid"]?.string { lines[uuid] = value }
        }
        return lines
    }

    @Test(arguments: [
        "ada.lovelace@example.com", "Analytical Engines Ltd", "0b6a4e1c-7d2f-4c3a-9e58-1f2a3b4c5d6e",
        "/Users/ada", "-Users-ada", "6f1e2d3c-4b5a-4968-8776-655443322110",
        "prompt_snapshot", "systemPrompt", "session_context", "credential_org",
        "\"thinking\"", "redacted_thinking", "signature",
        "ai-title", "custom-title", "pr-link", "cost-state", "last-prompt", "queue-operation", "file-history-snapshot",
        "hook_progress",
    ])
    func nothingOfTheSenderIsLeftInAnyFile(_ needle: String) throws {
        let result = try cleaned()

        for (name, text) in result.files.allTexts {
            #expect(!text.contains(needle), "\(name)")
        }
    }

    @Test func pathsBecomeThePlaceholderAndTheSessionGetsTheNewID() throws {
        let result = try cleaned()
        let transcript = try lines(result.files.transcript)
        let subagent = try lines(try #require(result.files.subagents["agent-a1.jsonl"]))

        #expect(transcript["u1"]?["cwd"] == .string("‹progetto›"))
        #expect(transcript["u1"]?["sessionId"] == .string(newSessionID))
        #expect(transcript["u1"]?["message"]?["content"]?.string?.contains("‹progetto›/Sources/Stampa.swift") == true)
        #expect(transcript["u12"]?["toolUseResult"]?["persistedOutputPath"]
            == .string("‹progetto›/.claude/projects/‹progetto›/\(newSessionID)/tool-results/toolu_big.txt"))
        #expect(subagent["b1"]?["sessionId"] == .string(newSessionID))
        #expect(result.files.subagentMetadata["agent-a1.meta.json"]?.contains("\"cwd\":\"‹progetto›\"") == true)
        #expect(result.files.toolResults["toolu_big.txt"]?.contains("Compiling ‹progetto›/Sources/Stampa.swift") == true)
    }

    @Test func aPathOnlyStartingLikeTheHomeStaysAsItIs() throws {
        let session = SessionFiles(transcript: """
        {"type":"user","uuid":"u1","parentUuid":null,"sessionId":"6f1e2d3c-4b5a-4968-8776-655443322110","message":{"role":"user","content":"/Users/adam/x e /Users/ada/x"}}
        """)
        let sender = TranscriptCleaner.Sender(worktree: "/Users/ada/dev", home: "/Users/ada", identity: [])

        let result = try TranscriptCleaner(sender: sender, newSessionID: "n").cleaning(session)

        #expect(result.files.transcript.contains("/Users/adam/x e ‹progetto›/x"))
    }

    @Test func theParentChainSkipsTheRemovedLines() throws {
        let result = try cleaned()
        let transcript = try lines(result.files.transcript)

        #expect(TranscriptCleaner.brokenLinks(in: result.files.transcript).isEmpty)
        #expect(TranscriptCleaner.brokenLinks(in: try #require(result.files.subagents["agent-a1.jsonl"])).isEmpty)
        // Identity and prompt attachments went: the instructions start the chain.
        #expect(transcript["a5"]?["parentUuid"] == .null)
        // A message of reasoning only went: the next one hangs from the question.
        #expect(transcript["u2"] == nil)
        #expect(transcript["u3"]?["parentUuid"] == .string("u1"))
        // A progress line went.
        #expect(transcript["u18"]?["parentUuid"] == .string("u17"))
        #expect(transcript["s2"]?["logicalParentUuid"] == .string("u14"))
    }

    @Test func reasoningBlocksGoAndTheTextNextToThemStays() throws {
        let result = try cleaned()
        let transcript = try lines(result.files.transcript)

        guard case let .array(blocks) = transcript["u6"]?["message"]?["content"] else {
            Issue.record("u6 has no content")
            return
        }
        #expect(blocks.map { $0["type"]?.string } == ["text"])
        #expect(result.removed[.reasoning] == 4)
    }

    @Test func theCountsSayWhatWent() throws {
        let result = try cleaned()

        #expect(result.removed[.identity] == 4)
        #expect(result.removed[.promptSnapshot] == 1)
        #expect(result.removed[.metadata] == 8)
        #expect(result.messageCount == 17)
    }

    @Test func aSecretDecidedTogliGoesEverywhere() throws {
        let secrets = Set(corpus.secrets.values)

        let result = try cleaned(removing: secrets)

        for (name, text) in result.files.allTexts {
            for secret in secrets {
                #expect(!text.contains(secret), "\(name)")
            }
        }
        #expect(result.files.toolResults["toolu_big.txt"]?.contains("‹tolto›") == true)
        #expect(result.files.subagents["agent-a1.jsonl"]?.contains("‹tolto›") == true)
    }

    @Test(arguments: [
        #"{"type":"mystery","uuid":"x"}"#: "mystery",
        #"{"type":"attachment","uuid":"x","attachment":{"type":"mystery"}}"#: "attachment/mystery",
    ])
    func anUnknownLineTypeStopsTheCleaning(_ line: String, type: String) throws {
        let transcript = #"{"type":"user","uuid":"u1","parentUuid":null,"message":{"role":"user","content":"Ciao"}}"#
            + "\n" + line + "\n"
        let cleaner = TranscriptCleaner(sender: corpus.sender, newSessionID: newSessionID)

        #expect(throws: TranscriptCleaner.Failure.unknownLineType(type, file: "transcript.jsonl", line: 2)) {
            try cleaner.cleaning(SessionFiles(transcript: transcript))
        }
    }

    @Test func aLineThatIsNotJSONStopsTheCleaning() {
        let cleaner = TranscriptCleaner(sender: corpus.sender, newSessionID: newSessionID)

        #expect(throws: TranscriptCleaner.Failure.unreadableLine(file: "agent-x.jsonl", line: 1)) {
            try cleaner.cleaning(SessionFiles(transcript: "", subagents: ["agent-x.jsonl": "{non è json"]))
        }
    }

    @Test func numbersAndFlagsKeepTheirType() throws {
        let line = try JSONValue.decoding(line: #"{"a":1,"b":1.5,"c":true,"d":null,"e":[0,false]}"#)

        #expect(try line.encodedLine() == #"{"a":1,"b":1.5,"c":true,"d":null,"e":[0,false]}"#)
    }
}
