/// One choice of "Rifai con…" (⌘⇧↑): a model near the one that answered, to ask the same Domanda again for this turn
/// only (spec 10, Interfaccia).
nonisolated struct RetryAlternative: Identifiable, Equatable, Sendable {
    /// Who answers if the user picks it.
    enum Target: Equatable, Sendable {
        /// A Claude model at an effort, through the Agent SDK.
        case claude(Scala.Step)
        /// An OpenAI-compatible endpoint, with the model the user set for it.
        case endpoint(OpenAICompatibleEndpoint)
        /// A model of the user's Copilot plan, at its own default effort, through `copilot`.
        case copilot(CopilotModel)
    }

    let target: Target
    /// How long the first token took the last time this choice answered, when known.
    var firstToken: Duration?

    /// The same for the same model at the same effort, or the same endpoint; it keys the first token's time too.
    var id: String {
        switch target {
        case let .claude(step): "claude.\(step.family.rawValue).\(step.effort?.rawValue ?? "-")"
        case let .endpoint(endpoint): endpoint.id
        case let .copilot(model): "copilot.\(model.id)"
        }
    }

    /// Whether it runs on this Mac: free, and the Domanda never leaves it.
    var isOnMac: Bool {
        if case let .endpoint(endpoint) = target { return endpoint.isOnMac }
        return false
    }

    /// Whether picking it sends the Domanda to a cloud that is not Claude, which needs the user's consent.
    var isOtherCloud: Bool {
        switch target {
        case .claude: false
        case let .endpoint(endpoint): !endpoint.isOnMac
        case .copilot: true
        }
    }

    /// The choices near the answer the user wants again, nearest first: the steps of the Scala just below and just
    /// above `current`, then the endpoints with a model, then the Copilot models not by Anthropic, without the one
    /// that answered.
    ///
    /// Claude always goes through `claude` (ADR 0011): a Claude model of the Copilot plan is not offered.
    ///
    /// - Parameters:
    ///   - current: The step of the Scala that answered; `nil` when an endpoint or Copilot answered, and then the
    ///     Claude steps offered are the router's usual middle ones, Sonnet and Opus at medium effort.
    ///   - copilotModels: The models of the user's Copilot plan, as `listModels()` lists them; empty without Copilot.
    ///   - answeredBy: The id of the endpoint, or of the alternative, that answered, if one did.
    static func alternatives(around current: Scala.Step?, on scala: Scala, endpoints: [OpenAICompatibleEndpoint],
                             copilotModels: [CopilotModel] = [], answeredBy: String?) -> [Self] {
        var steps: [Scala.Step]
        if let current {
            steps = [scala.steps.last { $0 < current }, scala.step(above: current)].compactMap(\.self)
        } else {
            steps = [ModelFamily.sonnet, .opus].compactMap { family in
                let ofFamily = scala.steps.filter { $0.family == family }
                return ofFamily.first { $0.effort == .medium } ?? ofFamily.first
            }
        }
        return steps.map { Self(target: .claude($0)) }
            + endpoints.filter { $0.id != answeredBy }.map { Self(target: .endpoint($0)) }
            + copilotModels.filter { $0.provider != .anthropic }.map { Self(target: .copilot($0)) }
                .filter { $0.id != answeredBy }
    }
}
