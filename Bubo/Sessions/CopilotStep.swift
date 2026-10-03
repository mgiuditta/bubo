import Foundation

/// A Copilot model at an effort, as a Sessione on Copilot keeps it (ADR 0012): the id `copilot` accepts, and the name
/// the Sessione shows even when `copilot` is not there to list its models.
nonisolated struct CopilotStep: Codable, Hashable, Sendable {
    /// What `copilot` accepts as its model, such as `gpt-6`.
    let model: String
    /// The model as `listModels()` names it.
    let modelName: String
    /// The reasoning effort; `nil` for the model's own.
    let effort: Effort?

    /// The step as the Sessione names it, such as «GPT-6 · medio»; the model alone without effort.
    var name: String {
        guard let effort else { return modelName }
        return String(localized: "\(modelName) · \(String(localized: effort.label))",
                      comment: "Model and effort in the reason line, such as «Sonnet 5.5 · medio».")
    }

    /// The steps of the Scala of Copilot, weakest first: the models by credits per request, the cheapest first, and
    /// within a model its efforts, the lowest first (ADR 0012). The order of `listModels()` breaks the ties.
    ///
    /// - Parameter models: What `listModels()` listed for the user's plan.
    static func scala(of models: [CopilotModel]) -> [CopilotStep] {
        models.enumerated()
            .sorted { ($0.element.multiplier ?? 1, $0.offset) < ($1.element.multiplier ?? 1, $1.offset) }
            .flatMap { _, model in
                model.supportedEfforts.isEmpty
                    ? [CopilotStep(model: model.id, modelName: model.name, effort: nil)]
                    : model.supportedEfforts.sorted().map { CopilotStep(model: model.id, modelName: model.name, effort: $0) }
            }
    }
}
