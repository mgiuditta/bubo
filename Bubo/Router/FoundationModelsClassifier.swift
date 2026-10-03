import Foundation
import FoundationModels

/// Classifies a request with Apple's on-device model in two guided generations, nothing on the network: Tipo and Categoria first,
/// then the Variante among those of that Categoria (#381), since the whole Catalogo does not fit the 4,096-token context.
///
/// It uses only `SystemLanguageModel.default`, which runs on the Mac; never Private Cloud Compute. Foundation Models gives no
/// probabilities, so the model names a second Tipo, `alternativa`, when it hesitates. The second schema is built at run time
/// because the Varianti come from `catalogo.json`; Tipo and Categoria are closed lists of choices, as an enum would be.
nonisolated struct FoundationModelsClassifier: ClassificationEngine {
    let catalogo: Catalogo
    /// Spec 10: under 300 ms on the device, otherwise the rules answer.
    let budget: Duration
    private let model: SystemLanguageModel
    private let schema: GenerationSchema
    private let instructions: String

    /// - Throws: An error of `GenerationSchema` if the Catalogo's names cannot form a schema.
    init(catalogo: Catalogo, budget: Duration = .milliseconds(300), model: SystemLanguageModel = .default) throws {
        self.catalogo = catalogo
        self.budget = budget
        self.model = model
        schema = try Self.schema()
        instructions = Self.instructions
    }

    /// Apple's model never leaves the Mac.
    var runsOnDevice: Bool { true }

    /// Whether the model can run now: Apple Intelligence on, the Mac eligible and the model downloaded.
    var isAvailable: Bool {
        model.availability == .available
    }

    /// Loads the model ahead of the first request, so that request fits the budget.
    func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(model: model, instructions: instructions).prewarm()
    }

    func classification(of input: ClassifierInput) async throws -> RequestClassification {
        guard isAvailable else { throw RequestClassification.Fallback.unavailable }
        // A new session per request: the transcript would otherwise grow into the 4,096-token context.
        let session = LanguageModelSession(model: model, instructions: instructions)
        let content: GeneratedContent
        do {
            content = try await session.respond(to: Self.prompt(for: input), schema: schema,
                                                options: Self.greedy).content
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale,
                LanguageModelSession.GenerationError.assetsUnavailable {
            throw RequestClassification.Fallback.unavailable
        } catch {
            throw RequestClassification.Fallback.failed
        }
        return try classification(from: content)
    }

    /// The Variante of `categoria` that clearly fits `input`, chosen by the model among that Categoria's alone;
    /// `nil` when none does.
    ///
    /// - Throws: `RequestClassification.Fallback` when the model cannot answer.
    func variante(of input: ClassifierInput, in categoria: Categoria) async throws -> Variante? {
        guard isAvailable else { throw RequestClassification.Fallback.unavailable }
        let candidates = catalogo.varianti(in: categoria)
        guard !candidates.isEmpty else { return nil }
        let session = LanguageModelSession(model: model, instructions: Self.instructions(choosingAmong: candidates))
        let content: GeneratedContent
        do {
            content = try await session.respond(to: Self.prompt(for: input), schema: try Self.schema(choosingAmong: candidates),
                                                options: Self.greedy).content
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale,
                LanguageModelSession.GenerationError.assetsUnavailable {
            throw RequestClassification.Fallback.unavailable
        } catch {
            throw RequestClassification.Fallback.failed
        }
        return (try? content.value(String?.self, forProperty: "variante"))
            .flatMap { $0.flatMap(catalogo.variante(named:)) }
            .flatMap { $0.categoria == categoria ? $0 : nil }
    }

    /// The classification the model's answer describes.
    ///
    /// - Throws: `RequestClassification.Fallback.failed` for a name outside the closed lists.
    func classification(from content: GeneratedContent) throws(RequestClassification.Fallback) -> RequestClassification {
        guard let tipo = try? content.value(String.self, forProperty: "tipo"),
              let type = RequestType(rawValue: tipo),
              let categoriaName = try? content.value(String.self, forProperty: "categoria"),
              let categoria = Categoria(rawValue: categoriaName)
        else { throw .failed }
        let alternative = (try? content.value(String?.self, forProperty: "alternativa")).flatMap { $0.flatMap(RequestType.init) }
        // A Variante of another Categoria is not a Variante for this one: Blob with the Categoria.
        let variante = (try? content.value(String?.self, forProperty: "variante"))
            .flatMap { $0.flatMap(catalogo.variante(named:)) }
            .flatMap { $0.categoria == categoria ? $0 : nil }
        return RequestClassification(candidate: type, alternative: alternative, categoria: categoria,
                                     variante: variante, engine: .foundationModels)
    }

    // MARK: Prompt

    /// Greedy sampling, so the same request gets the same verdict; Xcode 27 renamed its parameter.
    private static var greedy: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    private static func prompt(for input: ClassifierInput) -> String {
        guard !input.attachmentNames.isEmpty else { return input.text }
        return input.text + "\n\nAttachments: " + input.attachmentNames.joined(separator: ", ")
    }

    /// The schema of the first step: Tipo, its runner-up and Categoria.
    private static func schema() throws -> GenerationSchema {
        let tipi = RequestType.allCases.map(\.rawValue)
        let root = DynamicGenerationSchema(name: "Classification", properties: [
            .init(name: "tipo", schema: DynamicGenerationSchema(name: "Tipo", anyOf: tipi)),
            .init(name: "alternativa", description: "Only if unsure: the second most likely tipo.",
                  schema: DynamicGenerationSchema(name: "Alternativa", anyOf: tipi), isOptional: true),
            .init(name: "categoria", schema: DynamicGenerationSchema(name: "Categoria", anyOf: Categoria.allCases.map(\.rawValue))),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The schema of the second step: at most one of `candidates`.
    private static func schema(choosingAmong candidates: [Variante]) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(name: "Choice", properties: [
            .init(name: "variante", description: "Only if one clearly fits the request.",
                  schema: DynamicGenerationSchema(name: "Variante", anyOf: candidates.map(\.nome)), isOptional: true),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The instructions of the second step: the name and description of each of `candidates`.
    static func instructions(choosingAmong candidates: [Variante]) -> String {
        """
        Choose the shape that best illustrates the user's request to an assistant on the Mac, only if one clearly fits.
        Requests are in Italian or English.
        \(candidates.map { "- \($0.nome): \($0.descrizione)" }.joined(separator: "\n"))
        """
    }

    private static let instructions = """
        Classify the user's request for a coding assistant on the Mac. Requests are in Italian or English.
        tipo, for work on a codebase (sessione):
        - sessione.pianifica: asks for a plan, steps or design before any change.
        - sessione.correzione-piccola: a small, precise fix or change in one to three files.
        - sessione.modifica-ampia: a feature or change across many files or the whole project.
        - sessione.esplora: understand or find something in the code without changing it.
        - sessione.revisione: review a diff, branch, pull request or change.
        tipo, for a question without a codebase (domanda):
        - domanda.fatto-breve: a short fact the model already knows.
        - domanda.riassunto: summarize an attached file or text.
        - domanda.scrittura: write or rewrite a text: mail, post, poem, message.
        - domanda.ragionamento: think it through: compare, decide, prove, solve.
        - domanda.ricerca-web: needs the web or current data: news, prices, weather, schedules.
        categoria is the theme of the request; chat when no other fits:
        - codice: code, apps, tools and the work of building software.
        - agente: what the assistant itself does: plans, memory, tools, sub-agents, its context.
        - ricerca: finding, searching, investigating, comparing sources.
        - mail: email, messages to send, inbox, post.
        - creativo: drawing, design, photos, video, writing for fun, crafts.
        - musica: music, instruments, songs, concerts, audio.
        - meteo: weather, climate, seasons' skies, natural phenomena of the sky.
        - tempo: time, dates, calendars, deadlines, timers, seasons.
        - finanza: money, prices, budgets, banks, taxes, shopping costs.
        - salute: health, body, medicine, fitness, food for health, sleep.
        - viaggi: travel, places, transport, maps, holidays.
        - chat: anything else: everyday life, animals, food, people, games, curiosity.
        """
}
