import Foundation

/// The engine and the model the turns of a Sessione run on (ADR 0012): Claude unless the user chose Copilot.
nonisolated struct EngineChoice: Codable, Hashable, Sendable {
    var engine: Session.Engine = .claude
    /// The Claude step; `nil` for the model and effort the user set in `claude`.
    var claudeModel: Scala.Step?
    /// The Copilot step; `nil` for the model the user chose in `copilot`.
    var copilotModel: CopilotStep?

    /// Claude with the model and effort of `claude`.
    static let claude = EngineChoice()

    /// The engine and model as the Sessione shows them, such as «Claude · Sonnet 5.5 · medio».
    var name: String {
        switch engine {
        case .claude:
            claudeModel.map { String(localized: "Claude · \($0.name)", comment: "Engine and model of a Sessione.") }
                ?? String(localized: "Claude · predefinito", comment: "Engine of a Sessione, with the model set in claude.")
        case .copilot:
            copilotModel.map { String(localized: "Copilot · \($0.name)", comment: "Engine and model of a Sessione.") }
                ?? String(localized: "Copilot · predefinito", comment: "Engine of a Sessione, with the model set in copilot.")
        }
    }

    /// The choice one step up the Scala of its engine; `nil` at the top or for the engine's own default.
    ///
    /// - Parameter copilotModels: The models of the user's Copilot plan, whose Scala a Copilot choice climbs.
    func stronger(copilotModels: [CopilotModel]) -> EngineChoice? {
        switch engine {
        case .claude:
            return claudeModel.flatMap(Scala(catalog: nil).step(above:)).map { EngineChoice(engine: .claude, claudeModel: $0) }
        case .copilot:
            let steps = CopilotStep.scala(of: copilotModels)
            guard let copilotModel, let index = steps.firstIndex(of: copilotModel), index + 1 < steps.count else {
                return nil
            }
            return EngineChoice(engine: .copilot, copilotModel: steps[index + 1])
        }
    }
}
