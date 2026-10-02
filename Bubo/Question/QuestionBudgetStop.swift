import Foundation

/// A Domanda not sent, or stopped, because a Budget it counts in is spent (spec 18): what to ask again once the user
/// chooses.
nonisolated struct QuestionBudgetStop: Equatable, Sendable {
    /// The Budget spent.
    let scope: BudgetGuard.Scope
    /// The route stopped, which Continua solo questa volta asks again as it is.
    let route: Route
    /// The endpoint picked in "Rifai con…", when the Domanda was asked again with it; `nil` otherwise.
    var endpoint: OpenAICompatibleEndpoint?

    /// Whether the Domanda went to Claude with the API key: Passa all'abbonamento makes sense.
    var isClaude: Bool {
        endpoint == nil && route.endpoint == nil
    }
}
