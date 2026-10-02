import Foundation
import FoundationModels

/// Classifies a request with Apple's on-device model: Tipo, Categoria and Variante in one guided generation, nothing on the network.
///
/// It uses only `SystemLanguageModel.default`, which runs on the Mac; never Private Cloud Compute. Foundation Models gives no
/// probabilities, so the model names a second Tipo, `alternativa`, when it hesitates. The schema is built at run time because the
/// Varianti come from `catalogo.json`; Tipo and Categoria are closed lists of choices, as an enum would be.
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
        schema = try Self.schema(for: catalogo)
        instructions = Self.instructions(for: catalogo)
    }

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

    /// One schema for the whole answer; with hundreds of Varianti it should become two steps, Categoria then Variante.
    private static func schema(for catalogo: Catalogo) throws -> GenerationSchema {
        let tipi = RequestType.allCases.map(\.rawValue)
        let root = DynamicGenerationSchema(name: "Classification", properties: [
            .init(name: "tipo", schema: DynamicGenerationSchema(name: "Tipo", anyOf: tipi)),
            .init(name: "alternativa", description: "Only if unsure: the second most likely tipo.",
                  schema: DynamicGenerationSchema(name: "Alternativa", anyOf: tipi), isOptional: true),
            .init(name: "categoria", schema: DynamicGenerationSchema(name: "Categoria", anyOf: Categoria.allCases.map(\.rawValue))),
            .init(name: "variante", description: "Only a variante of the chosen categoria, if one clearly fits.",
                  schema: DynamicGenerationSchema(name: "Variante", anyOf: catalogo.varianti.map(\.nome)), isOptional: true),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func instructions(for catalogo: Catalogo) -> String {
        let varianti = catalogo.varianti.map { "- \($0.nome) (\($0.categoria.rawValue)): \($0.descrizione)" }
        return """
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
        categoria is the theme of the request; chat when no other fits.
        varianti:
        \(varianti.joined(separator: "\n"))
        """
    }
}
