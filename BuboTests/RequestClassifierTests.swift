import Foundation
import FoundationModels
import Testing
@testable import Bubo

/// The labelled set of #85: 200 requests, 20 per Tipo, half Italian and half English.
private struct LabelledSet: Decodable {
    struct Request: Decodable {
        let id: String
        let lingua: String
        let testo: String
        let tipo: RequestType
        let categoria: Categoria
        let variante: String?
        let allegati: [String]?

        var input: ClassifierInput { ClassifierInput(text: testo, attachmentNames: allegati ?? []) }
    }

    let richieste: [Request]

    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func load() throws -> LabelledSet {
        let url = root.appending(path: "BuboTests/Fixtures/richieste-etichettate.json")
        return try JSONDecoder().decode(LabelledSet.self, from: Data(contentsOf: url))
    }
}

private func catalogo() throws -> Catalogo {
    try Catalogo(json: Data(contentsOf: LabelledSet.root.appending(path: "Bubo/Catalogo/catalogo.json")))
}

/// The 95th percentile of `durations`.
private func p95(_ durations: [Duration]) -> Duration {
    let sorted = durations.sorted()
    return sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
}

/// How many of `requests` the `classify` closure gets right, and the report of the misses.
private func accuracy(of requests: [LabelledSet.Request],
                      classify: (ClassifierInput) async throws -> RequestClassification) async rethrows
    -> (tipo: Int, categoria: Int, variante: Int, latencies: [Duration], report: String) {
    var tipo = 0, categoria = 0, variante = 0
    var latencies: [Duration] = [], misses: [String] = []
    let clock = ContinuousClock()
    for request in requests {
        var result: RequestClassification?
        let elapsed = try await clock.measure { result = try await classify(request.input) }
        guard let result else { continue }
        latencies.append(elapsed)
        if result.type == request.tipo {
            tipo += 1
        } else {
            misses.append("\(request.id) \(request.tipo.rawValue) → \(result.type.rawValue): \(request.testo)")
        }
        categoria += result.categoria == request.categoria ? 1 : 0
        variante += result.variante?.nome == request.variante ? 1 : 0
    }
    let report = """
        Tipo \(tipo)/\(requests.count), Categoria \(categoria)/\(requests.count), Variante \(variante)/\(requests.count), \
        p95 \(p95(latencies))
        \(misses.joined(separator: "\n"))
        """
    return (tipo, categoria, variante, latencies, report)
}

struct RuleClassifierAccuracyTests {
    /// The gate of spec 10 for the engine every Mac and CI can run: the build fails below 85% of the Tipo.
    @Test func tipoIsRightOnAtLeast85PercentOfTheLabelledSet() async throws {
        let set = try LabelledSet.load()
        let rules = RuleClassifier(catalogo: try catalogo())
        let result = await accuracy(of: set.richieste) { rules.classification(of: $0) }
        Attachment.record(result.report, named: "regole.txt")
        #expect(set.richieste.count == 200)
        #expect(Double(result.tipo) / Double(set.richieste.count) >= 0.85, "\(result.report)")
    }

    @Test func italianAloneStaysAbove85Percent() async throws {
        let italian = try LabelledSet.load().richieste.filter { $0.lingua == "it" }
        let rules = RuleClassifier(catalogo: try catalogo())
        let result = await accuracy(of: italian) { rules.classification(of: $0) }
        #expect(Double(result.tipo) / Double(italian.count) >= 0.85, "\(result.report)")
    }

    @Test func p95IsUnder50Milliseconds() async throws {
        let set = try LabelledSet.load()
        let rules = RuleClassifier(catalogo: try catalogo())
        let result = await accuracy(of: set.richieste) { rules.classification(of: $0) }
        #expect(p95(result.latencies) < .milliseconds(50))
    }
}

/// Runs only on a Mac with Apple Intelligence on: CI and Macs without it skip it, and the rules gate the build.
@Suite(.enabled(if: SystemLanguageModel.default.isAvailable, "Apple Intelligence is not available on this Mac"),
       .timeLimit(.minutes(10)))
struct FoundationModelsAccuracyTests {
    @Test func tipoIsRightOnAtLeast85PercentWithin300Milliseconds() async throws {
        let set = try LabelledSet.load()
        let engine = try FoundationModelsClassifier(catalogo: try catalogo(), budget: .seconds(30))
        engine.prewarm()
        let result = try await accuracy(of: set.richieste) { try await engine.classification(of: $0) }
        Attachment.record(result.report, named: "foundation-models.txt")
        #expect(Double(result.tipo) / Double(set.richieste.count) >= 0.85, "\(result.report)")
        #expect(p95(result.latencies) <= .milliseconds(300), "\(result.report)")
    }
}

struct RuleClassifierTests {
    let rules: RuleClassifier

    init() throws {
        rules = RuleClassifier(catalogo: try catalogo())
    }

    @Test(arguments: [
        ("Plan the migration of the settings screen to SwiftUI, no edits yet.", RequestType.plan),
        ("Correggi il crash in LoginView quando la password è vuota.", .smallFix),
        ("Rivedi le modifiche di questo branch prima del merge.", .review),
        ("Riassumi questo documento.", .summary),
        ("Scrivimi una mail per disdire l'abbonamento.", .writing),
        ("Cerca le ultime notizie sulle elezioni di oggi.", .webSearch),
    ])
    func classifiesRequestsOutsideTheSet(text: String, expected: RequestType) {
        let attachments = expected == .summary ? ["documento.pdf"] : []
        #expect(rules.classification(of: ClassifierInput(text: text, attachmentNames: attachments)).type == expected)
    }

    @Test func italianElisionsDoNotBecomeEnglishWords() {
        #expect(RuleClassifier.normalized("Crasha all'apertura dell'app") == " crasha apertura app ")
    }

    @Test func aDomandaWithNoThemeIsBlobWithChat() {
        let result = rules.classification(of: ClassifierInput(text: "Qual è la capitale del Perù?"))
        #expect(result.type == .shortFact)
        #expect(result.categoria == .chat)
        #expect(result.variante == nil)
        #expect(result.engine == .rules)
    }

    @Test func theVarianteAlwaysBelongsToTheCategoria() throws {
        for request in try LabelledSet.load().richieste {
            let result = rules.classification(of: request.input)
            #expect(result.variante.map { $0.categoria == result.categoria } ?? true, "\(request.id)")
        }
    }
}

struct RequestClassificationTests {
    @Test func aHesitationTakesTheStrongerDefault() {
        let result = RequestClassification(candidate: .smallFix, alternative: .broadChange, categoria: .codice,
                                           variante: nil, engine: .rules)
        #expect(result.type == .broadChange)
        #expect(result.runnerUp == .smallFix)
    }

    @Test func aSureAnswerHasNoRunnerUp() {
        let result = RequestClassification(candidate: .review, alternative: .review, categoria: .codice,
                                           variante: nil, engine: .rules)
        #expect(result.type == .review)
        #expect(result.runnerUp == nil)
    }
}

struct FoundationModelsClassifierTests {
    let engine: FoundationModelsClassifier

    init() throws {
        engine = try FoundationModelsClassifier(catalogo: try catalogo())
    }

    @Test func readsTheGuidedAnswer() throws {
        let content = try GeneratedContent(json: """
            {"tipo": "sessione.correzione-piccola", "alternativa": "sessione.modifica-ampia",
             "categoria": "codice", "variante": "parentesi"}
            """)
        let result = try engine.classification(from: content)
        #expect(result.type == .broadChange)
        #expect(result.runnerUp == .smallFix)
        #expect(result.variante?.nome == "parentesi")
        #expect(result.engine == .foundationModels)
    }

    @Test func aVarianteOfAnotherCategoriaIsBlob() throws {
        let content = try GeneratedContent(json: #"{"tipo": "domanda.fatto-breve", "categoria": "meteo", "variante": "parentesi"}"#)
        let result = try engine.classification(from: content)
        #expect(result.categoria == .meteo)
        #expect(result.variante == nil)
        #expect(result.runnerUp == nil)
    }

    @Test func aTipoOutsideTheListFails() throws {
        let content = try GeneratedContent(json: #"{"tipo": "domanda.barzelletta", "categoria": "chat"}"#)
        #expect(throws: RequestClassification.Fallback.failed) { try engine.classification(from: content) }
    }
}

struct RequestClassifierTests {
    /// An engine that answers, fails or stalls as told.
    struct StubEngine: ClassificationEngine {
        enum Behavior: Sendable {
            case answer, fail(RequestClassification.Fallback), throwOther, stall
        }

        let behavior: Behavior
        var budget: Duration { .milliseconds(50) }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            switch behavior {
            case .answer:
                return RequestClassification(type: .reasoning, categoria: .finanza, variante: nil, engine: .foundationModels)
            case .fail(let reason):
                throw reason
            case .throwOther:
                throw CancellationError()
            case .stall:
                // Ignores cancellation, like an engine stuck in a call it cannot abandon.
                await Task.detached { try? await Task.sleep(for: .seconds(3)) }.value
                return RequestClassification(type: .reasoning, categoria: .finanza, variante: nil, engine: .foundationModels)
            }
        }
    }

    let input = ClassifierInput(text: "Rivedi la PR 12 prima del merge.")

    func classifier(_ behavior: StubEngine.Behavior) throws -> RequestClassifier {
        RequestClassifier(engines: [StubEngine(behavior: behavior)], rules: RuleClassifier(catalogo: try catalogo()))
    }

    @Test func theFirstEngineThatAnswersWins() async throws {
        let result = try await classifier(.answer).classification(of: input)
        #expect(result.engine == .foundationModels)
        #expect(result.type == .reasoning)
        #expect(result.fallback == nil)
    }

    @Test(arguments: [
        (StubEngine.Behavior.fail(.unavailable), RequestClassification.Fallback.unavailable),
        (.fail(.failed), .failed),
        (.throwOther, .failed),
    ])
    func aFailedEnginePassesTheTurnToTheRules(behavior: StubEngine.Behavior, reason: RequestClassification.Fallback) async throws {
        let result = try await classifier(behavior).classification(of: input)
        #expect(result.engine == .rules)
        #expect(result.type == .review)
        #expect(result.fallback == reason)
    }

    @Test func anEngineOverBudgetIsNotAwaited() async throws {
        let classifier = try classifier(.stall)
        var result: RequestClassification?
        let elapsed = await ContinuousClock().measure { result = await classifier.classification(of: input) }
        #expect(result?.engine == .rules)
        #expect(result?.fallback == .timedOut)
        #expect(elapsed < .seconds(2))
    }

    @Test func withoutEnginesTheRulesAnswerAlone() async throws {
        let result = await RequestClassifier(engines: [], rules: RuleClassifier(catalogo: try catalogo()))
            .classification(of: input)
        #expect(result.engine == .rules)
        #expect(result.fallback == nil)
    }

    /// Spec 10: zero bytes on the network while classifying. The engines may not reach for a network API at all.
    @Test(arguments: ["RequestClassifier", "RequestClassification", "RuleClassifier", "FoundationModelsClassifier"])
    func theClassifierHasNoNetworkPath(file: String) throws {
        let source = try String(contentsOf: LabelledSet.root.appending(path: "Bubo/Router/\(file).swift"), encoding: .utf8)
        for forbidden in ["URLSession", "PrivateCloudCompute", "Network", "NWConnection", "http"] {
            #expect(!source.contains(forbidden), "\(file) mentions \(forbidden)")
        }
    }
}
