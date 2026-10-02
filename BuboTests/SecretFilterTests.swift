import Foundation
import Testing
@testable import Bubo

/// The fixed set of 20 transcripts with planted secrets (spec 13).
nonisolated struct PlantedSecrets: Decodable, Sendable {
    struct Transcript: Decodable, Sendable, CustomTestStringConvertible {
        struct Message: Decodable, Sendable {
            var utente: Bool
            var testo: String
        }

        var titolo: String
        var messaggi: [Message]
        var segreti: [String]

        var testDescription: String { titolo }

        /// The messages as the bridge gives them, with the secrets whole again.
        var messages: [CLIConversation.Message] {
            messaggi.map { CLIConversation.Message(isFromUser: $0.utente, text: PlantedSecrets.joined($0.testo)) }
        }

        /// The secrets, whole again.
        var secrets: [String] { segreti.map(PlantedSecrets.joined) }
    }

    var trascrizioni: [Transcript]

    /// The fixture breaks each fake secret with `§`, so GitHub's secret scanning leaves it alone.
    static func joined(_ text: String) -> String { text.replacing("§", with: "") }

    static let all: [Transcript] = {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/trascrizioni-con-segreti.json")
        return (try? JSONDecoder().decode(PlantedSecrets.self, from: Data(contentsOf: url)).trascrizioni) ?? []
    }()
}

struct SecretFilterTests {
    let filter = SecretFilter()

    @Test func theFixedSetHasTwentyTranscripts() {
        #expect(PlantedSecrets.all.count == 20)
    }

    @Test(arguments: PlantedSecrets.all)
    func noPlantedSecretSurvivesTheFilter(_ transcript: PlantedSecrets.Transcript) {
        let text = transcript.messages.map(\.text).joined(separator: "\n\n")
        #expect(filter.containsSecret(text))

        let redacted = filter.redacting(text)

        for secret in transcript.secrets {
            #expect(!redacted.contains(secret))
        }
        #expect(redacted.contains(SecretFilter.replacement))
    }

    @Test(arguments: [
        "Commit 9f3c2a1b4d5e6f708192a3b4c5d6e7f809a1b2c3 su main.",
        "La Sessione 3F2504E0-4F89-11D3-9A0C-0305E82C3301 è Fusa.",
        "let tokenCount = tokens.count + 1",
        "func makeSecretFilter() -> SecretFilter { SecretFilter() }",
        "Ho cambiato `passwordField.isSecure = true` nella vista di login.",
        "Il branch bubo/riassunto-di-sessione è pronto per la revisione.",
        "https://github.com/mgiuditta/bubo/pull/118",
        "Costa 0,42 € e ha usato 12.345 token.",
    ])
    func commitHashesUUIDsAndCodeStayAsTheyAre(_ text: String) {
        #expect(filter.redacting(text) == text)
    }

    @Test func aLongTranscriptIsFilteredQuickly() {
        let text = String(repeating: "Ho aggiornato `SessionStore.swift` e la password_policy del modulo. ", count: 1_000)
        let clock = ContinuousClock()

        let elapsed = clock.measure { _ = filter.redacting(text) }

        #expect(elapsed < .seconds(2))
    }
}
