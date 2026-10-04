import Foundation
import Testing
@testable import Bubo

/// The Modello locale from the HUD (#94): the proposal made once, its answer, and the Domande that reach it. Every
/// server is `FakeChatServer`, and Claude is a bridge played by `/bin/sh`.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelLocalModelTests {
    let defaults = UserDefaults(suiteName: "QuestionModelLocalModelTests-\(UUID().uuidString)")!
    let settings: EndpointSettings
    let preferences = TypePreferences(defaults: UserDefaults(suiteName: "QuestionModelLocalModelTests-\(UUID().uuidString)")!)
    let ollama: OpenAICompatibleEndpoint

    init() {
        settings = EndpointSettings(defaults: defaults)
        ollama = LocalModelTests.ollama(loaded: #"{"models":[{"name":"llama3.2:latest"}]}"#,
                                        installed: #"{"models":[{"name":"llama3.2:latest"}]}"#)
        // Only this Ollama is on the Mac: LM Studio does not answer.
        settings.save(ollama)
        settings.save(LocalModelTests.switchedOff(.lmStudio))
    }

    /// A model whose Domande are all of `type`, with Apple Foundation Models off; online unless `isOnline` is false.
    func makeModel(type: RequestType = .summary, isOnline: Bool = true) -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { isOnline }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let rules = try? RuleClassifier(catalogo: Catalogo(bundle: .main))
        let intake = IntakePipeline(orb: orb, onDevice: .off) {
            guard let rules else { return nil }
            return RequestClassifier(engines: [QuestionModelTests.FixedEngine(type: type)], rules: rules)
        }
        return QuestionModel(cli: cli, orb: orb, intake: intake, bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", QuestionModelTests.sonnetBridge], apiKey: { nil },
                             endpoints: settings, preferences: preferences,
                             endpointClient: OpenAICompatibleClient(session: FakeChatServer.session),
                             endpointKey: { _ in nil },
                             localServers: LocalModelDetector(session: FakeChatServer.session),
                             prices: PriceTable(file: nil, bundled: PriceTableTests.snapshot))
    }

    @Test func theProposalIsMadeOnce() async {
        let model = makeModel()

        await model.lookForLocalModel()
        let offer = model.localModelOffer
        model.dismissLocalModelOffer()
        await model.lookForLocalModel()
        let again = makeModel()
        await again.lookForLocalModel()

        #expect(offer?.endpoint.id == ollama.id)
        #expect(offer?.model == "llama3.2:latest")
        #expect(model.localModelOffer == nil)
        #expect(again.localModelOffer == nil)
        #expect(EndpointSettings(defaults: defaults).hasOfferedLocalModel)
    }

    @Test func yesMakesItTheModelloLocaleForFattoBreveAndRiassunto() async {
        let model = makeModel()
        await model.lookForLocalModel()

        model.acceptLocalModel()

        #expect(settings.localModel?.id == ollama.id)
        #expect(settings.localModel?.model == "llama3.2:latest")
        #expect(preferences.choices == [.shortFact: .endpoint(id: ollama.id), .summary: .endpoint(id: ollama.id)])
        #expect(model.localModelOffer == nil)

        await QuestionModelTests.ask(model)
        #expect(model.answer == "dal Mac")
        #expect(model.routedAnswer?.route.reason == .preferred(.summary))
    }

    @Test func aPreferredServerSwitchedOffGivesTheDefaultAndSaysWhy() async {
        var off = LocalModelTests.switchedOff(.ollama)
        off.model = "llama3.2"
        settings.save(off)
        preferences.set(.endpoint(id: off.id), for: .summary)
        let model = makeModel()

        await QuestionModelTests.ask(model)

        #expect(model.answer == "risposta")
        #expect(model.routedAnswer?.endpoint == nil)
        #expect(model.routedAnswer?.route.pausedPreference == .localServerOff(off.name))
        #expect(preferences.choices[.summary] == .endpoint(id: off.id))
    }

    @Test func withoutANetworkTheModelloLocaleAnswersEveryTipo() async {
        var local = ollama
        local.model = "llama3.2"
        settings.save(local)
        settings.setLocalModel(local)
        let model = makeModel(type: .reasoning, isOnline: false)

        await QuestionModelTests.ask(model)

        #expect(model.answer == "dal Mac")
        #expect(model.routedAnswer?.route.reason == .offline(.reasoning))
        #expect(model.routedAnswer?.endpoint?.id == local.id)
    }
}
