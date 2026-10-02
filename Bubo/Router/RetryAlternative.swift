/// One choice of "Rifai con…" (⌘⇧↑): a model near the one that answered, to ask the same Domanda again for this turn
/// only (spec 10, Interfaccia).
nonisolated struct RetryAlternative: Identifiable, Equatable, Sendable {
    /// Who answers if the user picks it.
    enum Target: Equatable, Sendable {
        /// A Claude model at an effort, through the Agent SDK.
        case claude(Scala.Step)
        /// An OpenAI-compatible endpoint, with the model the user set for it.
        case endpoint(OpenAICompatibleEndpoint)
    }

    let target: Target
    /// How long the first token took the last time this choice answered, when known.
    var firstToken: Duration?

    /// The same for the same model at the same effort, or the same endpoint; it keys the first token's time too.
    var id: String {
        switch target {
        case let .claude(step): "claude.\(step.family.rawValue).\(step.effort?.rawValue ?? "-")"
        case let .endpoint(endpoint): endpoint.id
        }
    }

    /// Whether it runs on this Mac: free, and the Domanda never leaves it.
    var isOnMac: Bool {
        if case let .endpoint(endpoint) = target { return endpoint.isOnMac }
        return false
    }

    /// Whether picking it sends the Domanda to a cloud that is not Claude, which needs the user's consent.
    var isOtherCloud: Bool {
        if case let .endpoint(endpoint) = target { return !endpoint.isOnMac }
        return false
    }

    /// The choices near the answer the user wants again, nearest first: the steps of the Scala just below and just
    /// above `current`, then the endpoints with a model, without the one that answered.
    ///
    /// - Parameters:
    ///   - current: The step of the Scala that answered; `nil` when an endpoint answered, and then the Claude steps
    ///     offered are the router's usual middle ones, Sonnet and Opus at medium effort.
    ///   - answeredBy: The id of the endpoint that answered, if one did.
    static func alternatives(around current: Scala.Step?, on scala: Scala, endpoints: [OpenAICompatibleEndpoint],
                             answeredBy: String?) -> [Self] {
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
    }
}
