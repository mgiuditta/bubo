import Foundation
import Testing
@testable import Bubo

/// "Rifai con…" from the Domanda: the consent before a cloud that is not Claude, and what reaches it.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelRetryWithTests {
    let settings = EndpointSettings(defaults: UserDefaults(suiteName: "QuestionModelRetryWithTests-\(UUID().uuidString)")!)
    let endpoint: OpenAICompatibleEndpoint
    let preferences = TypePreferences(defaults: UserDefaults(suiteName: "QuestionModelRetryWithTests-\(UUID().uuidString)")!)
    let budgets = BudgetSettings(defaults: UserDefaults(suiteName: "QuestionModelRetryWithTests-\(UUID().uuidString)")!)

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
                                  prices: PriceTable(file: nil, bundled: PriceTableTests.snapshot), budgets: budgets)
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

    // Acceptance of #164: a model without a price on a provider with a Budget is said in the line.
    @Test func theLineSaysATurnWithoutAPriceIsOutsideTheBudget() async throws {
        budgets.budgets.providers["OpenAI"] = 10
        let model = await answeredModel(ledger: CostLedger())
        settings.grantConsent(to: endpoint)

        model.retry(with: try alternative(in: model))
        await model.answering?.value

        #expect(model.routedAnswer?.budgetNotice == .unpriced)
    }

    // Acceptance of #164: "Usa sempre per «Tipo»" on a provider past its threshold leaves it for the default.
    @Test func aPreferredCloudPastItsThresholdIsAvoided() async throws {
        let ledger = CostLedger()
        ledger.record(TurnUsage(mode: .apiKey, cost: 9, basis: .list, isComplete: true, models: [], origin: .reported),
                      turn: "t", question: UUID(), provider: "OpenAI")
        budgets.budgets.providers["OpenAI"] = 10
        settings.grantConsent(to: endpoint)
        preferences.set(.endpoint(id: endpoint.id), for: .writing)

        let model = await answeredModel(ledger: ledger, type: .writing)

        #expect(model.routedAnswer?.route.pausedPreference == .overBudget("OpenAI"))
        #expect(model.routedAnswer?.endpoint == nil)
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    /// A ledger with the Budget of OpenAI, $10, spent in full.
    func spentLedger() -> CostLedger {
        let ledger = CostLedger()
        ledger.record(TurnUsage(mode: .apiKey, cost: 10, basis: .list, isComplete: true, models: [], origin: .reported),
                      turn: "t", question: UUID(), provider: "OpenAI")
        budgets.budgets.providers["OpenAI"] = 10
        return ledger
    }

    // Acceptance of #165: at 100% no automatic choice goes to the provider, whatever the Tipo prefers.
    @Test(arguments: RequestType.allCases)
    func aPreferredCloudAtItsLimitIsNeverChosen(type: RequestType) async throws {
        let ledger = spentLedger()
        settings.grantConsent(to: endpoint)
        preferences.set(.endpoint(id: endpoint.id), for: type)

        let model = await answeredModel(ledger: ledger, type: type)

        #expect(model.routedAnswer?.endpoint == nil)
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    // Acceptance of #165: an explicit choice at 100% stops and asks; Continua solo questa volta sends it, once.
    @Test func anExplicitChoiceAtTheLimitGoesOnlyOnceConfirmed() async throws {
        let model = await answeredModel(ledger: spentLedger())
        settings.grantConsent(to: endpoint)

        model.retry(with: try alternative(in: model))
        await model.answering?.value
        #expect(model.failure == .budgetExhausted(QuestionBudgetStop(scope: .provider("OpenAI"), route: .retriedElsewhere,
                                                                     endpoint: endpoint)))
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)

        model.continueOverBudget()
        await model.answering?.value
        #expect(model.failure == nil)
        #expect(model.answer == "dal cloud")
        #expect(FakeChatServer.requests(at: endpoint.baseURL).count == 1)
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

    /// A Domanda with `attachments` answered by Sonnet, with `settings`' endpoints in "Rifai con…".
    func answeredModel(attachments: [Allegato]) async -> QuestionModel {
        let model = await answeredModel()
        // A Domanda of its own, not a seguito of the first: only its text and Allegati go.
        model.startNewQuestion()
        model.ask("Riassumi", attachments: attachments)
        await model.answering?.value
        return model
    }

    // Acceptance of #99: not a byte of an Allegato reaches a cloud without its confirmation.
    @Test func anAllegatoWaitsForItsConfirmation() async throws {
        let note = Allegato(name: "nota.md", text: "Testo riservato")
        let model = await answeredModel(attachments: [note])
        settings.grantConsent(to: endpoint)
        let alternative = try alternative(in: model)

        #expect(await model.attachmentVerdict(for: endpoint) == .needsConfirmation([note]))
        model.retry(with: alternative)
        await model.answering?.value

        #expect(model.failure == .attachmentsHeld)
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)

        model.confirm([note], for: endpoint)
        model.retry(with: alternative)
        await model.answering?.value

        #expect(model.failure == nil)
        let request = try #require(FakeChatServer.requests(at: endpoint.baseURL).first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["messages"] as? [[String: String]]
            == [["role": "user", "content": "Riassumi\n\n--- nota.md ---\nTesto riservato"]])
    }

    // Acceptance of #99: over the cap nothing is cut, and nothing is sent.
    @Test func anAllegatoOverTheCapIsNeverSent() async throws {
        let long = AttachmentCapTests.allegato(tokens: AttachmentPolicy.fixedCap + 1)
        let model = await answeredModel(attachments: [long])
        settings.grantConsent(to: endpoint)
        model.confirm([long], for: endpoint)

        #expect(await model.attachmentVerdict(for: endpoint)
            == .overCap(tokens: AttachmentPolicy.fixedCap + 1, cap: AttachmentPolicy.fixedCap))
        model.retry(with: try alternative(in: model))
        await model.answering?.value

        #expect(model.failure == .attachmentsHeld)
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    @Test func aConfirmationLastsOneDomanda() async throws {
        let note = Allegato(name: "nota.md", text: "Testo")
        let model = await answeredModel(attachments: [note])
        model.confirm([note], for: endpoint)
        #expect(await model.attachmentVerdict(for: endpoint) == .allowed)

        model.ask("Di nuovo", attachments: [note])
        await model.answering?.value
        #expect(await model.attachmentVerdict(for: endpoint) == .needsConfirmation([note]))
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
