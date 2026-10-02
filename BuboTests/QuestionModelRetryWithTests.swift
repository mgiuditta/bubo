import Foundation
import Testing
@testable import Bubo

/// "Rifai con…" from the Domanda: the consent before a cloud that is not Claude, and what reaches it.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelRetryWithTests {
    let settings = EndpointSettings(defaults: UserDefaults(suiteName: "QuestionModelRetryWithTests-\(UUID().uuidString)")!)
    let endpoint: OpenAICompatibleEndpoint
    let preferences = TypePreferences(defaults: UserDefaults(suiteName: "QuestionModelRetryWithTests-\(UUID().uuidString)")!)

    init() {
        var endpoint = OpenAICompatibleEndpoint.custom(
            named: "OpenAI", at: FakeChatServer.serve(.init(body: FakeChatServer.stream(["dal", " cloud"], input: 5, output: 2))))
        endpoint.model = "modello-prova"
        settings.save(endpoint)
        self.endpoint = endpoint
    }

    /// A Domanda answered by Sonnet through a bridge played by `/bin/sh`, with `settings`' endpoints in "Rifai con…".
    ///
    /// - Parameter type: The Tipo every Domanda is classified as; none is decided when `nil`.
    func answeredModel(ledger: CostLedger? = nil, type: RequestType? = nil) async -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let rules = try? RuleClassifier(catalogo: Catalogo(bundle: .main))
        let intake = IntakePipeline(orb: orb, onDevice: .off) {
            guard let type, let rules else { return nil }
            return RequestClassifier(engines: [QuestionModelTests.FixedEngine(type: type)], rules: rules)
        }
        let model = QuestionModel(cli: cli, orb: orb, intake: intake,
                                  bridgeExecutable: URL(filePath: "/bin/sh"),
                                  bridgeArguments: ["-c", QuestionModelTests.sonnetBridge], apiKey: { nil },
                                  endpoints: settings, preferences: preferences,
                                  endpointClient: OpenAICompatibleClient(session: FakeChatServer.session),
                                  endpointKey: { _ in "sk-prova" }, ledger: ledger,
                                  prices: PriceTable(file: nil, bundled: PriceTableTests.snapshot))
        await QuestionModelTests.ask(model)
        return model
    }

    func alternative(in model: QuestionModel) throws -> RetryAlternative {
        try #require(model.retryAlternatives.first { $0.target == .endpoint(endpoint) })
    }

    @Test func aCloudIsOfferedButNeedsConsent() async throws {
        let model = await answeredModel()

        let alternative = try alternative(in: model)

        #expect(model.needsConsent(for: alternative))
        #expect(model.retryAlternatives.first?.target == .claude(Scala.Step(family: .sonnet, effort: .low)))
    }

    // Acceptance of #92: without consent not a byte leaves for that cloud.
    @Test func withoutConsentNothingIsSent() async throws {
        let model = await answeredModel()

        model.retry(with: try alternative(in: model))
        await model.answering?.value

        #expect(model.failure == .endpoint(.consentMissing))
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    @Test func aDeclinedCloudLeavesRifaiConUntilTheNextDomanda() async throws {
        let model = await answeredModel()

        model.decline(endpoint)
        #expect(model.retryAlternatives.allSatisfy { $0.target != .endpoint(endpoint) })
        #expect(model.excludedEndpoints == [endpoint])

        await QuestionModelTests.ask(model)
        #expect(model.excludedEndpoints.isEmpty)
    }

    // Acceptance of #143: the Domanda's turn enters the ledger in "Domande", with its provider, tokens, unit and origin.
    @Test func theCloudsTurnIsRecordedInDomande() async throws {
        let ledger = CostLedger()
        let model = await answeredModel(ledger: ledger)
        settings.grantConsent(to: endpoint)

        model.retry(with: try alternative(in: model))
        await model.answering?.value

        let entry = try #require(ledger.entries.last)
        #expect(entry.project == nil)
        #expect(entry.provider == "OpenAI")
        #expect(entry.usage.origin == .unpriced)
        #expect(entry.usage.unit == .spesa)
        #expect(entry.usage.cost == nil)
        #expect(entry.usage.models.map(\.inputTokens) == [5])
        #expect(entry.usage.models.map(\.outputTokens) == [2])
        #expect(ledger.questionTotals()["OpenAI"]?[.spesa]?.value == 0)
    }

    @Test func withConsentTheCloudAnswersWithTheTextOnly() async throws {
        let model = await answeredModel()
        settings.grantConsent(to: endpoint)

        model.retry(with: try alternative(in: model))
        await model.answering?.value

        #expect(model.failure == nil)
        #expect(model.answer == "dal cloud")
        #expect(model.routedAnswer?.route.reason == .retried)
        #expect(model.routedAnswer?.answeringModel?.name == "modello-prova")
        #expect(model.routedAnswer?.cost == .tokens(7))
        let request = try #require(FakeChatServer.requests(at: endpoint.baseURL).first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["messages"] as? [[String: String]] == [["role": "user", "content": "Ciao"]])
        // The answer that came from the cloud offers Claude again, and not the same endpoint.
        #expect(model.retryAlternatives.map(\.target).contains(.claude(Scala.Step(family: .sonnet, effort: .medium))))
        #expect(model.retryAlternatives.allSatisfy { $0.target != .endpoint(endpoint) })
    }

    @Test func aClaudeStepIsRetriedForThisTurnOnly() async throws {
        let model = await answeredModel()

        model.retry(with: RetryAlternative(target: .claude(Scala.Step(family: .sonnet, effort: .low))))
        await model.answering?.value

        #expect(model.routedAnswer?.route == .retried(Scala.Step(family: .sonnet, effort: .low)))
        await QuestionModelTests.ask(model)
        #expect(model.routedAnswer?.route.reason == .unclassified)
    }

    // Acceptance of #409: the step picked with "Usa sempre per «Tipo»" answers the Tipo's next Domande.
    @Test func aClaudeStepBecomesTheTiposPreference() async throws {
        let model = await answeredModel(type: .writing)
        let opus = Scala.Step(family: .opus, effort: .high)

        model.retry(with: RetryAlternative(target: .claude(opus)), alwaysUse: true)
        await model.answering?.value
        #expect(preferences.choices == [.writing: .claude(opus)])

        await QuestionModelTests.ask(model)
        #expect(model.routedAnswer?.route == Route(family: .opus, model: "opus", effort: .high,
                                                   reason: .preferred(.writing)))
    }

    // Acceptance of #409: a cloud without consent never becomes a preference.
    @Test func aCloudWithoutConsentIsNotRemembered() async throws {
        let model = await answeredModel(type: .writing)

        model.retry(with: try alternative(in: model), alwaysUse: true)
        await model.answering?.value

        #expect(preferences.choices.isEmpty)
    }

    @Test func aPreferredCloudAnswersOnlyWhileItHasConsent() async throws {
        let model = await answeredModel(type: .writing)
        settings.grantConsent(to: endpoint)
        model.retry(with: try alternative(in: model), alwaysUse: true)
        await model.answering?.value
        #expect(preferences.choices == [.writing: .endpoint(id: endpoint.id)])

        await QuestionModelTests.ask(model)
        #expect(model.answer == "dal cloud")
        #expect(model.routedAnswer?.route.reason == .preferred(.writing))
        #expect(model.routedAnswer?.endpoint == endpoint)

        settings.revokeConsent(of: endpoint)
        await QuestionModelTests.ask(model)
        #expect(model.answer == "risposta")
        #expect(model.routedAnswer?.endpoint == nil)
    }

    // #101: a Domanda with Allegati never goes to an endpoint, preference or not.
    @Test func aDomandaWithAllegatiStaysWithClaude() async throws {
        let model = await answeredModel(type: .writing)
        settings.grantConsent(to: endpoint)
        preferences.set(.endpoint(id: endpoint.id), for: .writing)

        model.ask("Riassumi", attachments: [Allegato(name: "nota.txt", text: "testo")])
        await model.answering?.value

        #expect(model.answer == "risposta")
        #expect(model.routedAnswer?.endpoint == nil)
    }
}
