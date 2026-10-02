/// Chooses who answers a Domanda, and with which model and effort, from its Tipo di richiesta (spec 10).
///
/// Fatto breve and Riassunto go to Apple Foundation Models on the Mac when what they carry fits its context, and to
/// Haiku otherwise, saying why. It decides in microseconds and never waits for the catalog or a count: without one, `claude` gets the family's alias and the
/// SDK downgrades an effort the model lacks, which the reason line then shows as the effective one.
nonisolated struct ModelRouter {
    /// Routes the request `classification` describes; `nil` when no Tipo could be decided.
    ///
    /// - Parameters:
    ///   - fit: What Apple Foundation Models can take of the Richiesta, already measured.
    ///   - hasAttachments: Whether the Richiesta carries Allegati: without them, a Fatto breve that could not be
    ///     measured still goes on the Mac.
    ///   - readsOnDevice: Whether a model on the Mac may read every Allegato: not a folder, not an image.
    ///   - catalog: What `supportedModels()` listed, or `nil` when it was not read yet.
    func route(for classification: RequestClassification?, fit: OnDeviceFit = .unavailable,
               hasAttachments: Bool = false, readsOnDevice: Bool = true, in catalog: ModelCatalog?) -> Route {
        guard let classification else { return Route(family: nil, model: nil, effort: nil, reason: .unclassified) }
        let type = classification.type
        let fallback = Self.onDeviceFallback(for: type, fit: fit, hasAttachments: hasAttachments,
                                             readsOnDevice: readsOnDevice)
        if Self.onDeviceTypes.contains(type), fallback == nil {
            return .onDevice(type, runnerUp: classification.runnerUp)
        }
        let (family, effort) = Self.defaultChoice(for: type)
        guard let catalog else {
            return Route(family: family, model: family.alias, effort: effort,
                         reason: .type(type, runnerUp: classification.runnerUp), onDeviceFallback: fallback)
        }
        guard let entry = catalog.entry(for: family.alias) else {
            return Route(family: nil, model: nil, effort: nil, reason: .unavailable(type, family))
        }
        return Route(family: family, model: entry.value, effort: effort.flatMap { Self.effort($0, in: entry) },
                     reason: .type(type, runnerUp: classification.runnerUp), onDeviceFallback: fallback)
    }

    /// The Tipi Apple Foundation Models answers when they fit.
    static let onDeviceTypes: Set<RequestType> = [.shortFact, .summary]

    /// Why `type` cannot go on the Mac with `fit`; `nil` when it can, and for a Tipo that never does.
    ///
    /// Before macOS 26.4 nothing is counted: a Fatto breve without Allegati still goes on the Mac, while a Riassunto
    /// or an Allegato, which may be long, goes to Haiku.
    private static func onDeviceFallback(for type: RequestType, fit: OnDeviceFit,
                                         hasAttachments: Bool, readsOnDevice: Bool) -> Route.OnDeviceFallback? {
        guard onDeviceTypes.contains(type) else { return nil }
        guard readsOnDevice else { return .attachmentNotText }
        switch fit {
        case .fits: return nil
        case .tooLong: return hasAttachments ? .attachmentTooLong : .questionTooLong
        case .notMeasurable: return type == .shortFact && !hasAttachments ? nil : .attachmentNotMeasurable
        case .unavailable: return .unavailable
        }
    }

    /// The default Claude family and effort of `type`, from the table of spec 10; Haiku has no effort.
    ///
    /// Fatto breve and Riassunto take Haiku when Apple Foundation Models cannot answer them.
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
