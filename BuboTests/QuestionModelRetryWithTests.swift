import Foundation
import Testing
@testable import Bubo

/// "Rifai con…" from the Domanda: the consent before a cloud that is not Claude, and what reaches it.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelRetryWithTests {
    let settings = EndpointSettings(defaults: UserDefaults(suiteName: "QuestionModelRetryWithTests-\(UUID().uuidString)")!)
    let endpoint: OpenAICompatibleEndpoint

    init() {
        var endpoint = OpenAICompatibleEndpoint.custom(
            named: "OpenAI", at: FakeChatServer.serve(.init(body: FakeChatServer.stream(["dal", " cloud"], input: 5, output: 2))))
        endpoint.model = "modello-prova"
        settings.save(endpoint)
        self.endpoint = endpoint
    }

    /// A Domanda answered by Sonnet through a bridge played by `/bin/sh`, with `settings`' endpoints in "Rifai con…".
    func answeredModel(ledger: CostLedger? = nil) async -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let model = QuestionModel(cli: cli, orb: orb, intake: IntakePipeline(orb: orb, makeClassifier: { nil }),
                                  bridgeExecutable: URL(filePath: "/bin/sh"),
                                  bridgeArguments: ["-c", QuestionModelTests.sonnetBridge], apiKey: { nil },
                                  endpoints: settings, endpointClient: OpenAICompatibleClient(session: FakeChatServer.session),
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
}
