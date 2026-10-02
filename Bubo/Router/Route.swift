/// The router's decision for one Domanda: who answers, the model and effort `claude` gets, and why, for the reason line.
nonisolated struct Route: Equatable, Sendable {
    /// Who answers.
    enum Destination: Equatable, Sendable {
        /// Claude, through the agent bridge.
        case claude
        /// Apple Foundation Models, on the Mac.
        case onDevice
    }

    /// Why a Domanda that Apple Foundation Models could answer went to Claude instead.
    enum OnDeviceFallback: Equatable, Sendable {
        /// The Allegati are over `OnDeviceModel.attachmentLimit`.
        case attachmentTooLong
        /// No Allegato, but the text of the Domanda itself is over the limit.
        case questionTooLong
        /// macOS before 26.4 cannot count the tokens of an Allegato, and nothing is estimated.
        case attachmentNotMeasurable
        /// Apple Intelligence off, the Mac not eligible, or the model not ready.
        case unavailable
        /// The model failed before its first token.
        case failed
    }

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
    /// Who answers; with `.onDevice`, `family`, `model` and `effort` are `nil`.
    var destination: Destination = .claude
    /// Why Apple Foundation Models did not answer a Tipo it answers by default; `nil` when it did, or for other Tipi.
    var onDeviceFallback: OnDeviceFallback?

    /// The route of a Domanda of `type` that Apple Foundation Models answers on the Mac.
    static func onDevice(_ type: RequestType, runnerUp: RequestType?) -> Route {
        Route(family: nil, model: nil, effort: nil, reason: .type(type, runnerUp: runnerUp), destination: .onDevice)
    }

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

    /// The effort levels the chip in the prompt offers for this route's model, weakest first: the catalog's, without
    /// `max`, which is only for Sessioni; empty for a model without effort, and for Apple Foundation Models.
    ///
    /// Without a catalog, Haiku has none and the others go from low to very high: the SDK lowers what a model lacks.
    func effortLevels(in catalog: ModelCatalog?) -> [Effort] {
        guard let family else { return [] }
        if let catalog {
            return (catalog.entry(for: family.alias)?.supportedEffortLevels ?? []).filter { $0 < .max }.sorted()
        }
        return family == .haiku ? [] : [.low, .medium, .high, .xhigh]
    }

    /// The route the user picks with Tab (`forward`) or ⇧Tab from this one in the chip: the next Claude family of
    /// `catalog`, wrapping around, at the nearest effort it accepts.
    ///
    /// From Apple Foundation Models, or from `claude`'s default, Tab starts at the weakest family and ⇧Tab at the
    /// strongest.
    func choosingModel(forward: Bool, in catalog: ModelCatalog?) -> Route {
        let families = ModelFamily.allCases.filter { family in
            catalog.map { $0.entry(for: family.alias) != nil } ?? (family != .fable)
        }
        guard !families.isEmpty else { return self }
        let next: ModelFamily
        if let family, let index = families.firstIndex(of: family) {
            next = families[(index + (forward ? 1 : families.count - 1)) % families.count]
        } else {
            next = forward ? families[0] : families[families.count - 1]
        }
        let model = catalog?.entry(for: next.alias)?.value ?? next.alias
        let levels = Route(family: next, model: model, effort: nil, reason: .chosenByUser).effortLevels(in: catalog)
        let wanted = effort ?? .medium
        return Route(family: next, model: model, effort: levels.last { $0 <= wanted } ?? levels.first,
                     reason: .chosenByUser)
    }

    /// The route the user picks with ⌥↑ (`stronger`) or ⌥↓ in the chip: the same model one effort level away;
    /// `nil` for a model without effort, and past the strongest or the weakest level.
    func choosingEffort(stronger: Bool, in catalog: ModelCatalog?) -> Route? {
        let levels = effortLevels(in: catalog)
        guard !levels.isEmpty else { return nil }
        let next = if let effort {
            stronger ? levels.first { $0 > effort } : levels.last { $0 < effort }
        } else {
            levels.last { $0 <= .medium } ?? levels.first
        }
        return next.map { Route(family: family, model: model, effort: $0, reason: .chosenByUser) }
    }

    /// The step of the Scala this route ran on, as `answeringModel` says when known: the model that answered and its
    /// effective effort; `nil` when not even the family is known.
    func step(answeredBy answeringModel: AnsweringModel?) -> Scala.Step? {
        guard let answeringModel else { return family.map { Scala.Step(family: $0, effort: effort) } }
        return ModelFamily(model: answeringModel.model).map { Scala.Step(family: $0, effort: answeringModel.effort) }
    }
}
