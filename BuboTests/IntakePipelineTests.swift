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
