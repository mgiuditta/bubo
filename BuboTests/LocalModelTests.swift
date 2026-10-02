import Foundation
import Testing
@testable import Bubo

/// The Modello locale (#94): Ollama and LM Studio found on the Mac, the proposal made once, the router without a
/// network, and a preferred server that does not answer. Every server is `FakeChatServer`: never a real one.
@Suite(.timeLimit(.minutes(1)))
struct LocalModelTests {
    let detector = LocalModelDetector(session: FakeChatServer.session)
    let router = ModelRouter()

    /// Ollama at a fresh address on the Mac, whose `/api/ps` and `/api/tags` answer `loaded` and `installed`.
    static func ollama(loaded: String = #"{"models":[]}"#, installed: String = #"{"models":[]}"#,
                       answer: [String] = ["dal", " Mac"]) -> OpenAICompatibleEndpoint {
        let url = FakeChatServer.serve(.init(body: FakeChatServer.stream(answer)), onMac: true)
        FakeChatServer.serve(.init(body: loaded), at: "/api/ps", of: url)
        FakeChatServer.serve(.init(body: installed), at: "/api/tags", of: url)
        var endpoint = OpenAICompatibleEndpoint.known.first { $0.kind == .ollama }!
        endpoint.baseURL = url
        return endpoint
    }

    /// LM Studio at a fresh address on the Mac, whose `/api/v1/models` answers `listed`.
    static func lmStudio(listed: String) -> OpenAICompatibleEndpoint {
        let url = FakeChatServer.serve(.init(body: ""), onMac: true)
        FakeChatServer.serve(.init(body: listed), at: "/api/v1/models", of: url)
        var endpoint = OpenAICompatibleEndpoint.known.first { $0.kind == .lmStudio }!
        endpoint.baseURL = url
        return endpoint
    }

    /// A server on the Mac that does not answer.
    static func switchedOff(_ kind: OpenAICompatibleEndpoint.Kind) -> OpenAICompatibleEndpoint {
        var endpoint = OpenAICompatibleEndpoint.known.first { $0.kind == kind }!
        endpoint.baseURL = FakeChatServer.serve(.init(body: "", isOffline: true), onMac: true)
        return endpoint
    }

    static let installed = """
        {"models":[
          {"name":"qwen3:8b","modified_at":"2026-08-01T09:00:00.123456789+02:00"},
          {"name":"llama3.2:latest","modified_at":"2026-09-30T10:12:44.5-07:00"},
          {"name":"mistral:latest","modified_at":"2026-01-01T00:00:00Z"}
        ]}
        """

    // MARK: Detection

    @Test func ollamaProposesTheLoadedModel() async {
        let ollama = Self.ollama(loaded: #"{"models":[{"name":"qwen3:8b","context_length":8192}]}"#,
                                 installed: Self.installed)

        let offer = await detector.offer(among: [ollama])

        #expect(offer == LocalModelDetector.Offer(endpoint: ollama, model: "qwen3:8b"))
    }

    @Test func withoutALoadedModelOllamaProposesTheLatest() async {
        let ollama = Self.ollama(installed: Self.installed)

        let offer = await detector.offer(among: [ollama])

        #expect(offer?.model == "llama3.2:latest")
    }

    @Test func lmStudioProposesOnlyALoadedModel() async {
        let loaded = Self.lmStudio(listed: """
            {"models":[{"type":"embedding","key":"nomic-embed","loaded_instances":[{"id":"nomic-embed"}]},
                       {"type":"llm","key":"google/gemma-3-12b","loaded_instances":[{"id":"google/gemma-3-12b"}]}]}
            """)
        let unloaded = Self.lmStudio(listed: #"{"models":[{"type":"llm","key":"google/gemma-3-12b","loaded_instances":[]}]}"#)

        #expect(await detector.offer(among: [loaded])?.model == "google/gemma-3-12b")
        #expect(await detector.offer(among: [unloaded]) == nil)
    }

    @Test func aServerThatDoesNotAnswerIsSkipped() async {
        let lmStudio = Self.lmStudio(listed: #"{"models":[{"type":"llm","key":"gemma","loaded_instances":[{"id":"gemma"}]}]}"#)

        let offer = await detector.offer(among: [Self.switchedOff(.ollama), lmStudio])

        #expect(offer?.endpoint == lmStudio)
        #expect(await detector.offer(among: [Self.switchedOff(.ollama)]) == nil)
    }

    @Test func availabilityTellsAServerOffFromAMissingModel() async {
        var ollama = Self.ollama(installed: Self.installed)
        ollama.model = "llama3.2"
        var missing = ollama
        missing.model = "phi4"
        var off = Self.switchedOff(.ollama)
        off.model = "llama3.2"

        #expect(await detector.availability(of: ollama) == .available)
        #expect(await detector.availability(of: missing) == .modelMissing)
        #expect(await detector.availability(of: off) == .serverOff)
    }

    @Test func ollamaDatesAreReadWithTheirFraction() throws {
        let date = try #require(LocalModelDetector.date("2026-09-30T10:12:44.123456789+02:00"))
        #expect(date == Date(timeIntervalSince1970: 1_790_755_964))
    }

    // MARK: Router

    static func local(_ model: String = "llama3.2") -> OpenAICompatibleEndpoint {
        var endpoint = OpenAICompatibleEndpoint.known.first { $0.kind == .ollama }!
        endpoint.model = model
        return endpoint
    }

    @Test func withoutANetworkTheModelloLocaleAnswers() {
        let local = Self.local()
        let preferences = ModelRouter.Preferences(endpoints: [local], localModel: local, isOffline: true)

        let route = router.route(for: ModelRouterTests.classification(.writing), fit: .fits(tokens: 100), preferences: preferences,
                                 in: ModelRouterTests.catalog)

        #expect(route.endpoint == local)
        #expect(route.reason == .offline(.writing))
    }

    @Test func withoutANetworkOrAModelloLocaleAppleFMAnswers() {
        let local = Self.local()
        let switchedOff = ModelRouter.Preferences(endpoints: [local], localModel: local,
                                                  localOutages: [local.id: .serverOff], isOffline: true)

        let withoutLocal = router.route(for: ModelRouterTests.classification(.reasoning), fit: .fits(tokens: 100),
                                        preferences: ModelRouter.Preferences(isOffline: true),
                                        in: ModelRouterTests.catalog)
        let localOff = router.route(for: ModelRouterTests.classification(.reasoning), fit: .fits(tokens: 100),
                                    preferences: switchedOff, in: ModelRouterTests.catalog)

        #expect(withoutLocal.destination == .onDevice)
        #expect(withoutLocal.reason == .offline(.reasoning))
        #expect(localOff.destination == .onDevice)
    }

    @Test func withANetworkTheRouterNeverPicksTheModelloLocaleAlone() {
        let local = Self.local()
        let preferences = ModelRouter.Preferences(endpoints: [local], localModel: local)

        let route = router.route(for: ModelRouterTests.classification(.shortFact), fit: .tooLong(tokens: 9_000),
                                 preferences: preferences, in: ModelRouterTests.catalog)

        #expect(route.endpoint == nil)
        #expect(route.family == .haiku)
    }

    @Test(arguments: [
        (LocalModelDetector.Availability.serverOff, Route.PausedPreference.localServerOff("Ollama")),
        (.modelMissing, .localModelMissing("Ollama")),
    ])
    func aPreferredServerThatCannotAnswerGivesTheDefault(outage: LocalModelDetector.Availability,
                                                         pause: Route.PausedPreference) {
        let local = Self.local()
        let preferences = ModelRouter.Preferences(choices: [.summary: .endpoint(id: local.id)], endpoints: [local],
                                                  localModel: local, localOutages: [local.id: outage])

        let route = router.route(for: ModelRouterTests.classification(.summary), fit: .fits(tokens: 100),
                                 preferences: preferences, in: ModelRouterTests.catalog)

        #expect(route.destination == .onDevice)
        #expect(route.reason == .type(.summary, runnerUp: nil))
        #expect(route.pausedPreference == pause)
    }

    @Test func theReasonLineSaysWhy() {
        let paused = Route(family: nil, model: nil, effort: nil, reason: .type(.summary, runnerUp: nil),
                           destination: .onDevice, pausedPreference: .localServerOff("Ollama"))
        let offline = Route(family: nil, model: nil, effort: nil, reason: .offline(.shortFact), destination: .onDevice)

        let pausedLine = String(localized: RouterLine.reason(for: paused))
        let offlineLine = String(localized: RouterLine.reason(for: offline))

        #expect(pausedLine.contains("Ollama"))
        #expect(pausedLine.contains(RouterLine.appleFM))
        #expect(offlineLine.contains(RouterLine.appleFM))
        #expect(pausedLine != offlineLine)
    }
}
