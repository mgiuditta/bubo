import Foundation
import Testing
@testable import Bubo

/// The Conversazione ripulita marks what Bubo took out and never shows a secret whole.
struct DeliveryPreviewLineTests {
    let secret = SecretScanner.Finding(ruleID: "github-pat", source: .knownPrefix, value: "ghp_finto0000000000000000",
                                       locations: [])

    func line(_ text: String, uuid: String = "u1") throws -> String {
        let value = JSONValue.object([
            "type": .string("user"), "uuid": .string(uuid),
            "message": .object(["role": .string("user"), "content": .string(text)]),
        ])
        return try value.encodedLine()
    }

    @Test func secretsAndPlaceholdersAreMarked() throws {
        let jsonl = try line("in ‹progetto›/x usa \(secret.value) ora")

        let lines = DeliveryPreviewLine.lines(of: jsonl, findings: [secret])

        #expect(lines.count == 1)
        #expect(lines.first?.segments == [
            .plain("in "), .removed("‹progetto›"), .plain("/x usa "), .secret(secret.id), .plain(" ora"),
        ])
    }

    @Test func aLongMessageIsCutWithoutShowingPartOfASecret() throws {
        let padding = String(repeating: "a", count: DeliveryPreviewLine.characterLimit - 5)
        let jsonl = try line(padding + secret.value + String(repeating: "b", count: 50))

        let segments = try #require(DeliveryPreviewLine.lines(of: jsonl, findings: [secret]).first?.segments)
        let plain = segments.compactMap { segment -> String? in
            if case let .plain(text) = segment { return text }
            return nil
        }.joined()

        #expect(!plain.contains("ghp_"))
        #expect(segments.contains(.secret(secret.id)))
    }

    @Test func linesOutsideTheConversationAreNotShown() throws {
        let attachment = try JSONValue.object(["type": .string("attachment"), "uuid": .string("a1")]).encodedLine()

        #expect(DeliveryPreviewLine.lines(of: attachment, findings: []).isEmpty)
    }
}
