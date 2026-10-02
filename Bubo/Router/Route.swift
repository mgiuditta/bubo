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
        /// "Rifai più forte": one step up the Scala, for this turn only.
        case stronger
        /// "Rifai con…": the model the user picked among the near ones, for this turn only.
        case retried
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

    /// The route of `step`, one step up the Scala after "Rifai più forte".
    static func stronger(_ step: Scala.Step) -> Route {
        Route(family: step.family, model: step.family.alias, effort: step.effort, reason: .stronger)
    }

    /// The route of `step` picked in "Rifai con…".
    static func retried(_ step: Scala.Step) -> Route {
        Route(family: step.family, model: step.family.alias, effort: step.effort, reason: .retried)
    }

    /// The route of a Domanda an OpenAI-compatible endpoint answers, picked in "Rifai con…": not `claude`'s.
    static let retriedElsewhere = Route(family: nil, model: nil, effort: nil, reason: .retried)

    /// The step of the Scala this route ran on, as `answeringModel` says when known: the model that answered and its
    /// effective effort; `nil` when not even the family is known.
    func step(answeredBy answeringModel: AnsweringModel?) -> Scala.Step? {
        guard let answeringModel else { return family.map { Scala.Step(family: $0, effort: effort) } }
        return ModelFamily(model: answeringModel.model).map { Scala.Step(family: $0, effort: answeringModel.effort) }
    }
}
