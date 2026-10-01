/// The router's decision for one Domanda: the model and effort `claude` gets, and why, for the reason line.
nonisolated struct Route: Equatable, Sendable {
    /// Why the router chose what it chose.
    enum Reason: Equatable, Sendable {
        /// The default of the Tipo; with `runnerUp`, the stronger default of the two Tipi the classifier hesitated over.
        case type(RequestType, runnerUp: RequestType?)
        /// The Tipo's default family is not in the user's catalog: `claude` answers with its own default model.
        case unavailable(RequestType, ModelFamily)
        /// No Tipo could be decided: `claude` answers with its own default model.
        case unclassified
        /// The user picked the model for this turn.
        case chosenByUser
    }

    /// The family the router asked for; `nil` when `claude` picks.
    let family: ModelFamily?
    /// What `claude` gets as its model, an alias such as `sonnet`; `nil` for the model the user set in `claude`.
    let model: String?
    /// The effort asked for; `nil` for the model's default, and always for a model without effort.
    let effort: Effort?
    let reason: Reason

    /// The route of a turn whose model the user picked, such as `sonnet` after a limit: no effort, `claude`'s default.
    static func chosen(_ model: String) -> Route {
        Route(family: ModelFamily(rawValue: model), model: model, effort: nil, reason: .chosenByUser)
    }
}
