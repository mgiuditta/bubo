/// Chooses the model and effort of a Domanda from its Tipo di richiesta, resolved on the user's catalog (spec 10).
///
/// It decides in microseconds and never waits for the catalog: without one, `claude` gets the family's alias and the
/// SDK downgrades an effort the model lacks, which the reason line then shows as the effective one.
nonisolated struct ModelRouter {
    /// Routes the request `classification` describes; `nil` when no Tipo could be decided.
    ///
    /// - Parameter catalog: What `supportedModels()` listed, or `nil` when it was not read yet.
    func route(for classification: RequestClassification?, in catalog: ModelCatalog?) -> Route {
        guard let classification else { return Route(family: nil, model: nil, effort: nil, reason: .unclassified) }
        let type = classification.type
        let (family, effort) = Self.defaultChoice(for: type)
        guard let catalog else {
            return Route(family: family, model: family.alias, effort: effort,
                         reason: .type(type, runnerUp: classification.runnerUp))
        }
        guard let entry = catalog.entry(for: family.alias) else {
            return Route(family: nil, model: nil, effort: nil, reason: .unavailable(type, family))
        }
        return Route(family: family, model: entry.value, effort: effort.flatMap { Self.effort($0, in: entry) },
                     reason: .type(type, runnerUp: classification.runnerUp))
    }

    /// The default family and effort of `type`, from the table of spec 10; Haiku has no effort.
    ///
    /// Fatto breve goes to Haiku until Apple Foundation Models answers Domande (#89).
    static func defaultChoice(for type: RequestType) -> (ModelFamily, Effort?) {
        switch type {
        case .plan, .review: (.opus, .high)
        case .broadChange, .reasoning: (.opus, .medium)
        case .smallFix, .writing: (.sonnet, .medium)
        case .explore, .webSearch: (.sonnet, .low)
        case .summary, .shortFact: (.haiku, nil)
        }
    }

    /// The strongest level of `entry` up to `wanted`: never a level the model would refuse or downgrade.
    private static func effort(_ wanted: Effort, in entry: ModelCatalog.Entry) -> Effort? {
        entry.supportedEffortLevels.filter { $0 <= wanted }.max()
    }
}
