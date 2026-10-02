import Foundation
import Testing
@testable import Bubo

/// The PriceTable and the turns of the Domande priced with it (#143).
@Suite(.timeLimit(.minutes(1)))
struct PriceTableTests {
    /// A table with made-up prices, the shape of models.dev: tests never depend on today's real prices.
    static let snapshot = PriceTable.Snapshot(date: Date(timeIntervalSince1970: 1_790_000_000), etag: "\"v1\"", providers: [
        "openai": .init(models: ["gpt-prova": .init(cost: .init(input: 2, output: 8, cacheRead: Decimal(string: "0.5")))]),
        "google": .init(models: ["gemini-prova": .init(cost: .init(input: 1, output: 10, tiers: [
            .init(input: 2, output: 15, tier: .init(type: "context", size: 200_000)),
        ]))]),
        "xai": .init(models: ["grok-prova": .init(cost: .init(input: 3, output: 15))]),
    ])

    static func endpoint(_ kind: OpenAICompatibleEndpoint.Kind, model: String,
                         at address: String = "https://api.example.com/v1") -> OpenAICompatibleEndpoint {
        let known = OpenAICompatibleEndpoint.known.first { $0.kind == kind }
        var endpoint = known ?? .custom(named: "Prova", at: URL(string: address)!)
        endpoint.model = model
        return endpoint
    }

    @Test func aFigureIsTokensTimesThePricePerMillion() throws {
        let cost = try #require(Self.snapshot.cost(of: "gpt-prova", at: "openai"))

        // 800 uncached at $2, 200 cached at $0.50, 500 out at $8, per million.
        #expect(cost.figure(input: 1_000, cachedInput: 200, output: 500) == Decimal(string: "0.0057"))
    }

    @Test func aLongContextTakesItsTiersPrices() throws {
        let cost = try #require(Self.snapshot.cost(of: "models/gemini-prova", at: "google"))

        #expect(cost.figure(input: 200_000, cachedInput: 0, output: 0) == Decimal(string: "0.2"))
        #expect(cost.figure(input: 200_001, cachedInput: 0, output: 0) == Decimal(string: "0.400002"))
    }

    @Test func aKnownModelIsPricedWithTheTablesDate() {
        let usage = OpenAICompatibleClient.Usage(input: 1_000, output: 500, cachedInput: 200)

        let turn = UsageReader.turn(usage, from: Self.endpoint(.openAI, model: "gpt-prova"), prices: Self.snapshot)

        #expect(turn.origin == .priceTable)
        #expect(turn.unit == .spesa)
        #expect(turn.cost == Decimal(string: "0.0057"))
        #expect(turn.priceDate == Self.snapshot.date)
        #expect(turn.models.first?.inputTokens == 800)
        #expect(turn.models.first?.cacheReadTokens == 200)
    }

    // Acceptance of #143: a model the table lacks is "senza prezzo", with 0 figures made up.
    @Test func aModelMissingFromTheTableHasNoFigure() {
        let turn = UsageReader.turn(.init(input: 10, output: 5), from: Self.endpoint(.openAI, model: "gpt-ignoto"),
                                    prices: Self.snapshot)

        #expect(turn.origin == .unpriced)
        #expect(turn.cost == nil)
        #expect(turn.priceDate == nil)
        #expect(turn.models.first?.outputTokens == 5)
    }

    @Test func openRoutersReportedCostWinsOverTheTable() {
        let usage = OpenAICompatibleClient.Usage(input: 10, output: 5, cost: Decimal(string: "0.0003"))

        let turn = UsageReader.turn(usage, from: Self.endpoint(.custom, model: "openai/gpt-prova",
                                                               at: "https://openrouter.ai/api/v1"),
                                    prices: Self.snapshot)

        #expect(turn.origin == .reported)
        #expect(turn.cost == Decimal(string: "0.0003"))
    }

    @Test func xAIIsKnownByItsAddress() {
        let turn = UsageReader.turn(.init(input: 1_000_000, output: 0),
                                    from: Self.endpoint(.custom, model: "grok-prova", at: "https://api.x.ai/v1"),
                                    prices: Self.snapshot)

        #expect(turn.origin == .priceTable)
        #expect(turn.cost == 3)
    }

    @Test(arguments: [OpenAICompatibleEndpoint.Kind.ollama, .lmStudio])
    func aServerOnTheMacIsFreeWithItsTokens(kind: OpenAICompatibleEndpoint.Kind) {
        let turn = UsageReader.turn(.init(input: 10, output: 5), from: Self.endpoint(kind, model: "llama"),
                                    prices: Self.snapshot)

        #expect(turn.origin == .free)
        #expect(turn.unit == .gratis)
        #expect(turn.cost == 0)
        #expect(turn.models.first?.inputTokens == 10)
    }

    @Test func appleFMIsFreeAndIncompleteWithoutCounts() {
        #expect(UsageReader.onDevice(input: 40, output: 12).unit == .gratis)
        #expect(UsageReader.onDevice(input: 40, output: 12).isComplete)
        #expect(!UsageReader.onDevice(input: nil, output: nil).isComplete)
    }

    // Acceptance of #143: the table works offline, from the bundle.
    @Test func theBundledTableWorksOffline() throws {
        let bundled = try #require(PriceTable.bundled)
        let models = try #require(bundled.providers["openai"]?.models)

        #expect(Set(bundled.providers.keys) == Set(PriceTable.Snapshot.providerIDs))
        #expect(models.values.contains { $0.cost?.figure(input: 1_000, cachedInput: 0, output: 1_000) != nil })
        #expect(PriceTable(file: nil).snapshot == bundled)
    }

    // Acceptance of #143: prices older than 30 days say which day they are from.
    @Test func oldPricesAreTold() {
        let date = Self.snapshot.date
        #expect(!Self.snapshot.isOld(at: date.addingTimeInterval(29 * 24 * 60 * 60)))
        #expect(Self.snapshot.isOld(at: date.addingTimeInterval(31 * 24 * 60 * 60)))

        var answer = RoutedAnswer(route: .retriedElsewhere, provider: .openAI, endpoint: Self.endpoint(.openAI, model: "gpt-prova"))
        answer.usage = UsageReader.turn(.init(input: 1_000, output: 500), from: Self.endpoint(.openAI, model: "gpt-prova"),
                                        prices: Self.snapshot)
        #expect(answer.cost == .estimate(Decimal(string: "0.006")!, pricesOf: date))
    }

    // Acceptance of #143: the refresh is the feature's only call, a GET with nothing of the user's.
    @Test func theRefreshIsABareGetOnceADay() async throws {
        let catalog = #"{"openai":{"name":"OpenAI","models":{"gpt-nuovo":{"id":"gpt-nuovo","cost":{"input":1,"output":4}},"senza-costo":{"id":"senza-costo"}}},"altro":{"models":{}}}"#
        let source = FakeChatServer.serve(.init(body: catalog, headers: ["ETag": "\"v2\""]))
        let defaults = try #require(UserDefaults(suiteName: "PriceTableTests-\(UUID().uuidString)"))
        let file = FileManager.default.temporaryDirectory.appending(path: "Prezzi-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let table = PriceTable(file: file, bundled: Self.snapshot, source: source, session: FakeChatServer.session,
                               defaults: defaults)
        let now = Date.now

        await table.updateIfDue(now: now)
        await table.updateIfDue(now: now.addingTimeInterval(60 * 60))

        let requests = FakeChatServer.requests(at: source)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.body.isEmpty)
        #expect(request.headers["Authorization"] == nil)
        #expect(request.headers["Cookie"] == nil)
        #expect(request.headers["If-None-Match"] == "\"v1\"")
        #expect(table.snapshot.providers.keys.sorted() == ["openai"])
        #expect(table.snapshot.providers["openai"]?.models.keys.sorted() == ["gpt-nuovo"])
        #expect(table.snapshot.etag == "\"v2\"")
        #expect(table.snapshot.date == now)
        // The refreshed copy outlives the launch.
        #expect(PriceTable(file: file, bundled: Self.snapshot, defaults: defaults).snapshot.etag == "\"v2\"")
    }

    @Test func turnedOffTheTableNeverCalls() async throws {
        let source = FakeChatServer.serve(.init(body: "{}"))
        let defaults = try #require(UserDefaults(suiteName: "PriceTableTests-\(UUID().uuidString)"))
        let table = PriceTable(file: nil, bundled: Self.snapshot, source: source, session: FakeChatServer.session,
                               defaults: defaults)

        table.updatesDaily = false
        await table.updateIfDue()

        #expect(FakeChatServer.requests(at: source).isEmpty)
        #expect(table.snapshot == Self.snapshot)
    }
}
