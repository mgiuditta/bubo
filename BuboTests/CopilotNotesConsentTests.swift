import Foundation
import Testing
@testable import Bubo

/// The notes of the Secondo cervello to Copilot (#678): asked once, revocable, and without them the Domanda goes as
/// before.
@Suite(.timeLimit(.minutes(1)))
struct CopilotNotesConsentTests {
    let defaults = UserDefaults(suiteName: "CopilotNotesConsentTests-\(UUID().uuidString)")!

    @Test func buboAsksOnlyWithASecondBrainAndCopilotsConsent() {
        let settings = EndpointSettings(defaults: defaults)
        #expect(!settings.needsCopilotNotesConsent(hasSecondBrain: true))

        settings.grantCopilotConsent()

        #expect(settings.needsCopilotNotesConsent(hasSecondBrain: true))
        #expect(!settings.needsCopilotNotesConsent(hasSecondBrain: false))
    }

    @Test func declinedItIsNeverAskedAgainNorGiven() {
        let settings = EndpointSettings(defaults: defaults)
        settings.grantCopilotConsent()

        settings.answerCopilotNotesConsent(allowing: false)

        let relaunched = EndpointSettings(defaults: defaults)
        #expect(!relaunched.needsCopilotNotesConsent(hasSecondBrain: true))
        #expect(!relaunched.allowsCopilotNotes)
    }

    @Test func allowedItLastsUntilRevoked() {
        let settings = EndpointSettings(defaults: defaults)
        settings.grantCopilotConsent()

        settings.answerCopilotNotesConsent(allowing: true)
        #expect(EndpointSettings(defaults: defaults).allowsCopilotNotes)
        #expect(!settings.needsCopilotNotesConsent(hasSecondBrain: true))

        settings.revokeCopilotNotesConsent()
        let relaunched = EndpointSettings(defaults: defaults)
        #expect(!relaunched.allowsCopilotNotes)
        #expect(!relaunched.needsCopilotNotesConsent(hasSecondBrain: true))
        // Copilot keeps its own consent for the Domande.
        #expect(relaunched.allowsCopilot)
    }

    @Test func theCommandCarriesTheProfiloAndTheRegole() throws {
        let line = try BridgeCommand.askCopilotQuestion(id: "c1", prompt: "Ciao", directory: URL(filePath: "/tmp/vuota"),
                                                        copilot: URL(filePath: "/opt/homebrew/bin/copilot"),
                                                        secondBrain: "## Bubo/Regole.md").line()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["brain"] as? String == "## Bubo/Regole.md")
    }

    /// A bridge that answers whether the command had the Profilo and the Regole, after a `cerca` of the Domanda.
    static func bridge() -> AgentBridge {
        let script = #"""
            read line; id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
            case "$line" in *'"brain":"## Profilo"'*) brain=con ;; *) brain=senza ;; esac
            echo "{\"v\":4,\"type\":\"search\",\"id\":\"s1\",\"query\":\"gatto\",\"conversation\":\"$id\"}"
            read found
            echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"$brain\"}"
            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                           environment: ["PATH": "/usr/bin:/bin"], basics: { "## Profilo" }) { query, _, _ in
            "trovato \(query)"
        }
    }

    @Test(arguments: [
        ([EndpointSettings.copilotConsentID, EndpointSettings.copilotNotesConsentID], true, "con"),
        ([EndpointSettings.copilotConsentID], true, "senza"),
        ([EndpointSettings.copilotConsentID, EndpointSettings.copilotNotesConsentID], false, "senza"),
    ])
    func theNotesGoOnlyWithTheirConsent(consents: [String], sharesNotes: Bool, expected: String) async throws {
        var searched: [String] = []
        let answer = try await Self.bridge().askCopilotQuestion(
            "Ciao", in: URL(filePath: "/tmp"), copilot: URL(filePath: "/opt/homebrew/bin/copilot"), consents: Set(consents),
            sharesNotes: sharesNotes,
            progress: { if case let .memory(.searched(query, _)) = $0 { searched.append(query) } }
        ).reduce("", +)
        #expect(answer == expected)
        // The calls of `cerca` reach the Domanda, for the Galassia and the Salvato line.
        #expect(searched == ["gatto"])
    }
}
