import Foundation
import Synchronization
import Testing
@testable import Bubo

@MainActor
struct IntakePipelineTests {
    /// An engine that reports what the Orb showed when the classification started, then answers with `variante`.
    nonisolated struct WitnessEngine: ClassificationEngine {
        let orb: OrbControls
        let variante: Variante?
        let seen: @Sendable (OrbState?, Bool) -> Void
        var budget: Duration { .seconds(1) }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            let (state, isAnthropic) = await MainActor.run { (orb.questionState, orb.provider == .anthropic) }
            seen(state, isAnthropic)
            return RequestClassification(type: .webSearch, categoria: .ricerca, variante: variante, engine: .foundationModels)
        }
    }

    let catalogo: Catalogo
    let orb = OrbControls()

    init() throws {
        catalogo = try Catalogo(bundle: .main)
        orb.provider = nil
    }

    func pipeline(engine: (any ClassificationEngine)? = nil, onDevice: OnDeviceModel = .off) -> IntakePipeline {
        let rules = RuleClassifier(catalogo: catalogo)
        return IntakePipeline(orb: orb, onDevice: onDevice) {
            RequestClassifier(engines: engine.map { [$0] } ?? [], rules: rules)
        }
    }

    /// An engine that always answers `type`.
    nonisolated struct FixedEngine: ClassificationEngine {
        let type: RequestType
        var budget: Duration { .milliseconds(300) }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            RequestClassification(type: type, categoria: .chat, variante: nil, engine: .foundationModels)
        }
    }

    /// An engine on the Mac that counts its classifications and gives the Variante named after the last word, if any.
    nonisolated struct CountingEngine: ClassificationEngine {
        let catalogo: Catalogo
        let counter = Counter()
        var runsOnDevice: Bool
        var count: Int { counter.value }
        var budget: Duration { .seconds(1) }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            counter.increment()
            let last = input.text.split { !$0.isLetter }.last.map { String($0).lowercased() }
            let variante = last.flatMap(catalogo.variante(named:))
            return RequestClassification(type: .webSearch, categoria: variante?.categoria ?? .chat, variante: variante,
                                         engine: .foundationModels)
        }
    }

    /// The rules, standing for Apple Foundation Models on the Mac.
    nonisolated struct OnDeviceRules: ClassificationEngine {
        let rules: RuleClassifier
        var budget: Duration { .seconds(1) }
        var runsOnDevice: Bool { true }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            rules.classification(of: input)
        }
    }

    /// An engine whose classification leaves the Variante to a second step, which answers `variante`.
    nonisolated struct TwoStepEngine: ClassificationEngine {
        let variante: Variante
        var budget: Duration { .seconds(1) }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            RequestClassification(type: .webSearch, categoria: variante.categoria, variante: nil, engine: .foundationModels)
        }

        func variante(of input: ClassifierInput, in categoria: Categoria) async throws -> Variante? {
            variante
        }
    }

    // #381: the Blob with the Categoria does not wait for the second step; its Variante morphs on arrival.
    @Test func theSecondStepMorphsAfterTheBlob() async throws {
        let lente = try #require(catalogo.variante(named: "lente"))
        let intake = pipeline(engine: TwoStepEngine(variante: lente))

        let submission = await intake.submit(Richiesta(text: "Trova il file dei colori."), to: .anthropic)
        #expect(submission.classification?.variante == nil)
        #expect(orb.variante == nil)

        for _ in 0..<100 where orb.variante == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(orb.variante == lente)
        #expect(intake.forecast?.variante == lente)
    }

    @Test func aSecondStepAfterTheAnswerLeavesTheOrbAlone() async throws {
        let lente = try #require(catalogo.variante(named: "lente"))
        let intake = pipeline(engine: TwoStepEngine(variante: lente))

        let submission = await intake.submit(Richiesta(text: "Trova il file dei colori."), to: .anthropic)
        intake.finish(submission)

        try await Task.sleep(for: .milliseconds(200))
        #expect(orb.variante == nil)
    }

    // #106: the final text confirms the prediction, so the classifier is not asked again.
    @Test func aConfirmedPredictionMorphsWithoutTheClassifier() async throws {
        let lente = try #require(catalogo.variante(named: "lente"))
        let engine = CountingEngine(catalogo: catalogo, runsOnDevice: true)
        let intake = pipeline(engine: engine)
        intake.predict(Richiesta(text: "cerca con la lente"))
        #expect(orb.variante == nil, "the Orb waits for the release")
        let submission = await intake.submit(Richiesta(text: "Cerca con la lente."), to: .anthropic)
        #expect(engine.count == 1)
        #expect(orb.variante == lente)
        #expect(submission.classification?.variante == lente)
    }

    @Test func anotherFinalTextWaitsForTheClassifier() async throws {
        let engine = CountingEngine(catalogo: catalogo, runsOnDevice: true)
        let intake = pipeline(engine: engine)
        intake.predict(Richiesta(text: "cerca con la lente"))
        let submission = await intake.submit(Richiesta(text: "Cerca con la lente, anzi no"), to: .anthropic)
        #expect(engine.count == 2)
        #expect(submission.classification?.variante == nil)
        #expect(orb.variante == nil)
    }

    // Without Apple Foundation Models nothing is predicted: never a remote engine, never the rules.
    @Test func withoutTheModelOnTheMacNothingIsPredicted() async {
        let engine = CountingEngine(catalogo: catalogo, runsOnDevice: false)
        let intake = pipeline(engine: engine)
        intake.predict(Richiesta(text: "cerca con la lente"))
        _ = await intake.submit(Richiesta(text: "cerca con la lente"), to: .anthropic)
        #expect(engine.count == 1)
        let rulesOnly = RequestClassifier(engines: [], rules: RuleClassifier(catalogo: catalogo))
        #expect(await rulesOnly.prediction(of: ClassifierInput(text: "cerca con la lente")) == nil)
    }

    // A prediction serves only the release that follows it.
    @Test func aTypedRichiestaForgetsThePrediction() async {
        let engine = CountingEngine(catalogo: catalogo, runsOnDevice: true)
        let intake = pipeline(engine: engine)
        intake.predict(Richiesta(text: "cerca con la lente"))
        _ = await intake.submit(Richiesta(text: "Che ore sono?"), to: .anthropic)
        _ = await intake.submit(Richiesta(text: "cerca con la lente"), to: .anthropic)
        #expect(engine.count == 3)
    }

    @Test(arguments: [("Cerca le notizie di oggi.", "cerca le notizie di oggi"),
                      ("What's the weather, today?", "what s the weather today")])
    func theComparisonIgnoresCaseAndPunctuation(final: String, partial: String) {
        #expect(IntakePipeline.key(of: ClassifierInput(text: final)) == ClassifierInput(text: partial))
    }

    @Test func theAllegatiMustMatchToo() {
        let withNote = ClassifierInput(text: "riassumi", attachmentNames: ["nota.txt"])
        #expect(IntakePipeline.key(of: withNote) != IntakePipeline.key(of: ClassifierInput(text: "riassumi")))
    }

    /// #106: with the prediction holding, the Morph starts within 350 ms of the release and ends within 1.7 s.
    @Test func aConfirmedPredictionStartsTheMorphWithin350Milliseconds() async throws {
        let intake = pipeline(engine: OnDeviceRules(rules: RuleClassifier(catalogo: catalogo)))
        let text = "Che tempo fa domani a Roma? Previsioni di pioggia"
        intake.predict(Richiesta(text: text))
        let clock = ContinuousClock()
        let released = clock.now
        _ = await intake.submit(Richiesta(text: text), to: .anthropic)
        let decided = (clock.now - released) / .seconds(1)
        let variante = try #require(orb.variante)
        var director = MorphDirector()
        director.request(variante, at: decided)
        director.advance(to: decided)
        #expect(decided + 1 / 60 <= 0.35, "the next frame starts the Morph")
        director.advance(to: 1.7)
        #expect(director.frame == MorphFrame(from: variante, to: variante, progress: 1, opacity: 1))
    }

    /// #106 on the labelled set, heard word by word: the Orb never moves before the release, the prediction never
    /// morphs where the classifier on the final text would not, and the Categoria stays right on at least 90%.
    @Test func thePartialsOfTheLabelledSetMakeNoFalseMorph() async throws {
        let rules = RuleClassifier(catalogo: catalogo)
        var categorie = 0, falseMorphs: [String] = []
        let richieste = try LabelledRequest.load()
        for request in richieste {
            orb.variante = nil
            let intake = pipeline(engine: OnDeviceRules(rules: rules))
            let words = request.testo.split(separator: " ")
            let attachments = request.allegati.map { Allegato(name: $0, text: "") }
            for count in 1...words.count {
                intake.predict(Richiesta(text: words.prefix(count).joined(separator: " "), attachments: attachments))
                await Task.yield()
            }
            #expect(orb.variante == nil)
            let submission = await intake.submit(Richiesta(text: request.testo, attachments: attachments), to: .anthropic)
            let final = rules.classification(of: ClassifierInput(text: request.testo, attachmentNames: request.allegati))
            if orb.variante != final.variante {
                falseMorphs.append("\(request.id) \(final.variante?.nome ?? "Blob") → \(orb.variante?.nome ?? "Blob")")
            }
            categorie += submission.classification?.categoria.rawValue == request.categoria ? 1 : 0
        }
        #expect(richieste.count == 200)
        #expect(falseMorphs.isEmpty, "\(falseMorphs.joined(separator: "\n"))")
        #expect(Double(categorie) / Double(richieste.count) >= 0.9)
    }

    @Test func appleFMTakesTheNeutralTinta() async {
        let intake = pipeline(engine: FixedEngine(type: .shortFact), onDevice: .fitting)
        let submission = await intake.submit(Richiesta(text: "Qual è la capitale del Perù?"), to: .anthropic)
        #expect(submission.route.destination == .onDevice)
        #expect(orb.provider == nil)
        #expect(intake.forecast?.provider == nil)

        // Haiku answers instead: the Tinta follows it.
        intake.answer(submission, movedTo: .anthropic)
        #expect(orb.provider == .anthropic)
        #expect(intake.forecast?.provider == .anthropic)
    }

    // The count runs alongside the classification, within its budget: one too slow means Haiku, not a wait.
    @Test(.timeLimit(.minutes(1)))
    func theMeasureDoesNotDelayTheDecision() async {
        let slow = OnDeviceModel(isAvailable: { true }, tokenCount: { _ in
            try await Task.sleep(for: .seconds(30))
            return 10
        })
        let intake = pipeline(engine: FixedEngine(type: .summary), onDevice: slow)
        let clock = ContinuousClock()
        let start = clock.now
        let submission = await intake.submit(
            Richiesta(text: "Riassumi", attachments: [Allegato(name: "nota.txt", text: "Testo lungo")]), to: .anthropic)
        #expect(clock.now - start < .seconds(2))
        #expect(submission.route.family == .haiku)
        #expect(submission.route.onDeviceFallback == .attachmentNotMeasurable)
        #expect(orb.provider == .anthropic)
    }

    @Test func theOrbThinksWithTheTintaBeforeTheDecision() async throws {
        let lente = try #require(catalogo.variante(named: "lente"))
        let witness = Witness()
        let intake = pipeline(engine: WitnessEngine(orb: orb, variante: lente) { state, isAnthropic in
            witness.record(state, isAnthropic)
        })
        let submission = await intake.submit(Richiesta(text: "Cerca le notizie di oggi"), to: .anthropic)
        #expect(witness.seen == [.init(state: .thinking, isAnthropic: true)])
        #expect(orb.variante == lente)
        #expect(intake.forecast == IntakePipeline.Forecast(variante: lente, provider: .anthropic))
        #expect(submission.classification?.variante == lente)
    }

    // The router decides within the decision step, so the route is there when the Morph starts.
    @Test func theRouteComesWithTheDecision() async throws {
        let lente = try #require(catalogo.variante(named: "lente"))
        let intake = pipeline(engine: WitnessEngine(orb: orb, variante: lente) { _, _ in })
        let submission = await intake.submit(Richiesta(text: "Cerca le notizie di oggi"), to: .anthropic)
        #expect(submission.route == Route(family: .sonnet, model: "sonnet", effort: .low,
                                          reason: .type(.webSearch, runnerUp: nil)))
    }

    @Test func parlaOutlastsTheAnswerAndThenGivesTheOrbBack() async {
        let intake = pipeline()
        let submission = await intake.submit(Richiesta(text: "Che ore sono a Lima?"), to: .anthropic)
        intake.beginWorking(on: submission)
        intake.beginSpeaking(on: submission)
        #expect(orb.questionState == .speaking)
        intake.beginWorking(on: submission)
        #expect(orb.questionState == .speaking)
        intake.finish(submission)
        #expect(orb.questionState == .speaking)
        orb.voiceLevel = 0.5
        intake.endSpeaking(on: submission)
        #expect(orb.questionState == nil)
        #expect(orb.voiceLevel == nil)
    }

    @Test func aShortSintesiParlataGoesBackToWork() async {
        let intake = pipeline()
        let submission = await intake.submit(Richiesta(text: "Che ore sono a Lima?"), to: .anthropic)
        intake.beginSpeaking(on: submission)
        intake.endSpeaking(on: submission)
        #expect(orb.questionState == .working)
    }

    @Test func theFirstTokenTurnsTheOrbToWorkAndTheEndGivesItBack() async {
        orb.state = .listening
        let intake = pipeline()
        let submission = await intake.submit(Richiesta(text: "Qual è la capitale del Perù?"), to: .anthropic)
        #expect(orb.displayedState == .thinking)
        intake.beginWorking(on: submission)
        #expect(orb.displayedState == .working)
        intake.finish(submission)
        #expect(orb.displayedState == .listening)
        #expect(intake.forecast == nil)
    }

    @Test func anUncertainVarianteLeavesTheBlob() async throws {
        let nuvola = try #require(catalogo.variante(named: "nuvola"))
        orb.variante = nuvola
        let intake = pipeline()
        _ = await intake.submit(Richiesta(text: "Qual è la capitale del Perù?"), to: nil)
        #expect(orb.variante == nil)
        #expect(intake.forecast == IntakePipeline.Forecast(variante: nil, provider: nil))
    }

    @Test func aStaleRichiestaNoLongerMovesTheOrb() async {
        let intake = pipeline()
        let first = await intake.submit(Richiesta(text: "Che tempo fa domani a Roma?"), to: .anthropic)
        let second = await intake.submit(Richiesta(text: "Qual è la capitale del Perù?"), to: .anthropic)
        intake.beginWorking(on: first)
        intake.finish(first)
        #expect(orb.displayedState == .thinking)
        intake.finish(second)
        #expect(orb.displayedState == .idle)
    }

    @Test func withoutAClassifierTheOrbStillThinks() async {
        let intake = IntakePipeline(orb: orb) { nil }
        let submission = await intake.submit(Richiesta(text: "Ciao"), to: .anthropic)
        #expect(submission.classification == nil)
        #expect(submission.route.reason == .unclassified)
        #expect(orb.displayedState == .thinking)
        #expect(intake.forecast == nil)
    }

    /// #87: the Morph starts within 600 ms of the send and ends within 1.7 s, from the rules' decision to the Regia.
    @Test func theMorphStartsAndEndsWithinTheBudget() async throws {
        let intake = pipeline()
        let clock = ContinuousClock()
        let sent = clock.now
        _ = await intake.submit(Richiesta(text: "Che tempo fa domani a Roma? Previsioni di pioggia"), to: .anthropic)
        let decided = (clock.now - sent) / .seconds(1)
        let variante = try #require(orb.variante)
        var director = MorphDirector()
        director.request(variante, at: decided)
        director.advance(to: decided)
        #expect(decided + 1 / 60 <= 0.6, "the next frame starts the Morph")
        director.advance(to: 1.7)
        #expect(director.frame == MorphFrame(from: variante, to: variante, progress: 1, opacity: 1))
    }
}

/// What the witness engine saw, kept across its isolation.
nonisolated private final class Witness: Sendable {
    struct Sight: Equatable {
        let state: OrbState?
        let isAnthropic: Bool
    }

    private let sights = Mutex<[Sight]>([])

    var seen: [Sight] { sights.withLock { $0 } }

    func record(_ state: OrbState?, _ isAnthropic: Bool) {
        sights.withLock { $0.append(Sight(state: state, isAnthropic: isAnthropic)) }
    }
}

/// One request of the labelled set of #85, with what the voice test needs.
private struct LabelledRequest: Decodable {
    let id: String
    let testo: String
    let categoria: String
    let allegati: [String]

    private enum CodingKeys: String, CodingKey { case id, testo, categoria, allegati }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        testo = try container.decode(String.self, forKey: .testo)
        categoria = try container.decode(String.self, forKey: .categoria)
        allegati = try container.decodeIfPresent([String].self, forKey: .allegati) ?? []
    }

    private struct Set: Decodable {
        let richieste: [LabelledRequest]
    }

    static func load() throws -> [LabelledRequest] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/richieste-etichettate.json")
        return try JSONDecoder().decode(Set.self, from: Data(contentsOf: url)).richieste
    }
}

/// How many times an engine classified, across its isolation.
nonisolated final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() {
        count.withLock { $0 += 1 }
    }
}
