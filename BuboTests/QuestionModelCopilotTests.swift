import Foundation
import Testing
@testable import Bubo

/// "Rifai con…" a Copilot model from the Domanda (#541): the HUD and the Panel's bubble share this model.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelCopilotTests {
    let preferences = TypePreferences(defaults: UserDefaults(suiteName: "QuestionModelCopilotTests-\(UUID().uuidString)")!)

    /// A bridge played by `/bin/sh`: Sonnet answers the Domande, `copilot` lists GPT-6 and Claude Sonnet and answers
    /// as GPT-6.
    static let bridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in
            *'"type":"copilotModels"'*)
              echo "{\"v\":4,\"type\":\"copilotModels\",\"id\":\"$id\",\"models\":[{\"id\":\"gpt-6\",\"name\":\"GPT-6\",\"supportedEfforts\":[\"low\",\"medium\",\"high\"],\"defaultEffort\":\"medium\"},{\"id\":\"claude-sonnet-5.5\",\"name\":\"Claude Sonnet 5.5\"}]}" ;;
            *'"type":"copilotQuestion"'*)
              echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"da copilot\"}"
              echo "{\"v\":4,\"type\":\"answeredBy\",\"id\":\"$id\",\"model\":\"gpt-6\",\"effort\":\"medium\"}"
              echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
            *)
              echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"risposta\"}"
              echo "{\"v\":4,\"type\":\"answeredBy\",\"id\":\"$id\",\"model\":\"claude-sonnet-5-5\",\"effort\":\"medium\"}"
              echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
          esac
        done
        """#

    /// A Domanda of Scrittura answered by Sonnet, with `copilot` found by `copilot`.
    func answeredModel(orb: OrbControls = OrbControls(), allowsCopilot: Bool = true,
                       copilot: @escaping () async -> URL? = { URL(filePath: "/opt/homebrew/bin/copilot") }) async -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let rules = try? RuleClassifier(catalogo: Catalogo(bundle: .main))
        let intake = IntakePipeline(orb: orb, onDevice: .off) {
            rules.map { RequestClassifier(engines: [QuestionModelTests.FixedEngine(type: .writing)], rules: $0) }
        }
        let endpoints = EndpointSettings(defaults: UserDefaults(suiteName: "QuestionModelCopilotTests-\(UUID().uuidString)")!)
        if allowsCopilot { endpoints.grantCopilotConsent() }
        let model = QuestionModel(cli: cli, orb: orb, intake: intake, bridgeExecutable: URL(filePath: "/bin/sh"),
                                  bridgeArguments: ["-c", Self.bridge], apiKey: { nil },
                                  endpoints: endpoints,
                                  preferences: preferences, copilot: copilot)
        await QuestionModelTests.ask(model)
        return model
    }

    func gpt(in model: QuestionModel) throws -> RetryAlternative {
        try #require(model.retryAlternatives.first { $0.target == .copilot(CopilotRoutingTests.gpt) })
    }

    @Test func rifaiConListsTheCopilotModelsOnlyOnceOpened() async throws {
        let model = await answeredModel()
        #expect(model.retryAlternatives.allSatisfy { if case .copilot = $0.target { false } else { true } })

        await model.readCopilotModels()

        // Claude Sonnet of the Copilot plan stays out: Claude goes through `claude`.
        let copilot = model.retryAlternatives.filter { if case .copilot = $0.target { true } else { false } }
        #expect(copilot.map(\.id) == ["copilot.gpt-6"])
    }

    // Acceptance of #541: "Rifai con" a Copilot model answers, with the vendor's Tinta and "via Copilot".
    @Test func rifaiConACopilotModelAnswersWithTheVendorsTinta() async throws {
        let orb = OrbControls()
        let model = await answeredModel(orb: orb)
        await model.readCopilotModels()

        model.retry(with: try gpt(in: model))
        await model.answering?.value

        #expect(model.failure == nil)
        #expect(model.answer == "da copilot")
        #expect(model.routedAnswer?.route == .copilot(CopilotRoutingTests.gpt, effort: nil, reason: .retried))
        #expect(model.routedAnswer?.provider == .openAI)
        #expect(orb.provider == .openAI)
        #expect(String(localized: RouterLine.reason(for: try #require(model.routedAnswer?.route))).hasSuffix("via Copilot"))
        // The answer leaves the Domanda's default alone.
        #expect(preferences.choices.isEmpty)
    }

    @Test func rifaiPiuForteClimbsTheCopilotModelsEfforts() async throws {
        let model = await answeredModel()
        await model.readCopilotModels()
        model.retry(with: try gpt(in: model))
        await model.answering?.value

        #expect(model.strongerRoute == .copilot(CopilotRoutingTests.gpt, effort: .high, reason: .stronger))
    }

    @Test func usaSemprePerMakesTheCopilotModelThePreference() async throws {
        let model = await answeredModel()
        await model.readCopilotModels()

        model.retry(with: try gpt(in: model), alwaysUse: true)
        await model.answering?.value
        #expect(preferences.choices[.writing] == .copilot(id: "gpt-6", name: "GPT-6"))

        await QuestionModelTests.ask(model)
        #expect(model.answer == "da copilot")
        #expect(model.routedAnswer?.route.reason == .preferred(.writing))
        #expect(model.routedAnswer?.provider == .openAI)
    }

    // #543: without the consent for Copilot, "Rifai con…" asks it first and nothing is sent.
    @Test func withoutConsentNothingGoesToCopilot() async throws {
        let model = await answeredModel(allowsCopilot: false)
        await model.readCopilotModels()
        let gpt = try gpt(in: model)
        #expect(model.needsConsent(for: gpt))

        model.retry(with: gpt, alwaysUse: true)
        await model.answering?.value

        #expect(model.failure == .endpoint(.consentMissing))
        #expect(model.answer.isEmpty)
        #expect(preferences.choices.isEmpty)
    }

    @Test func withoutAPaidCopilotNothingIsListedNorSent() async throws {
        let model = await answeredModel(copilot: { nil })
        await model.readCopilotModels()
        #expect(model.retryAlternatives.allSatisfy { if case .copilot = $0.target { false } else { true } })

        preferences.set(.copilot(id: "gpt-6", name: "GPT-6"), for: .writing)
        await QuestionModelTests.ask(model)

        #expect(model.failure == .copilotUnavailable)
        #expect(model.answer.isEmpty)
    }
}
