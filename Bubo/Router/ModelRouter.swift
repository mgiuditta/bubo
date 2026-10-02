/// Chooses who answers a Domanda, and with which model and effort, from its Tipo di richiesta (spec 10).
///
/// Fatto breve and Riassunto go to Apple Foundation Models on the Mac when what they carry fits its context, and to
/// Haiku otherwise, saying why. It decides in microseconds and never waits for the catalog or a count: without one, `claude` gets the family's alias and the
/// SDK downgrades an effort the model lacks, which the reason line then shows as the effective one.
nonisolated struct ModelRouter {
    /// What "Usa sempre per «Tipo»" asks of the router: the user's choice for each Tipo, and the endpoints that may
    /// answer one.
    struct Preferences: Equatable, Sendable {
        /// Who answers each Tipo with a preference.
        var choices: [RequestType: TypePreference] = [:]
        /// The endpoints with a model that may receive a Domanda: on the Mac, or in a cloud with the user's consent.
        var endpoints: [OpenAICompatibleEndpoint] = []

        /// No preference: every Tipo takes its default.
        static let none = Self()
    }

    /// Routes the request `classification` describes; `nil` when no Tipo could be decided.
    ///
    /// - Parameters:
    ///   - fit: What Apple Foundation Models can take of the Richiesta, already measured.
    ///   - hasAttachments: Whether the Richiesta carries Allegati: without them, a Fatto breve that could not be
    ///     measured still goes on the Mac.
    ///   - readsOnDevice: Whether a model on the Mac may read every Allegato: not a folder, not an image.
    ///   - preferences: The user's preferences, which replace the Tipo's default when they can answer; when one
    ///     cannot, the default answers and `Route.pausedPreference` says why.
    ///   - catalog: What `supportedModels()` listed, or `nil` when it was not read yet.
    func route(for classification: RequestClassification?, fit: OnDeviceFit = .unavailable,
               hasAttachments: Bool = false, readsOnDevice: Bool = true, preferences: Preferences = .none,
               in catalog: ModelCatalog?) -> Route {
        guard let classification else { return Route(family: nil, model: nil, effort: nil, reason: .unclassified) }
        let type = classification.type
        guard let choice = preferences.choices[type] else {
            return Self.defaultRoute(for: classification, fit: fit, hasAttachments: hasAttachments,
                                     readsOnDevice: readsOnDevice, in: catalog)
        }
        guard let pause = Self.pause(of: choice, preferences: preferences, hasAttachments: hasAttachments,
                                     in: catalog) else {
            return Self.preferredRoute(of: choice, for: type, preferences: preferences, in: catalog)
        }
        var route = Self.defaultRoute(for: classification, fit: fit, hasAttachments: hasAttachments,
                                      readsOnDevice: readsOnDevice, in: catalog)
        route.pausedPreference = pause
        return route
    }

    /// The route of the Tipo's default, from the table of spec 10, within `catalog`.
    private static func defaultRoute(for classification: RequestClassification, fit: OnDeviceFit,
                                     hasAttachments: Bool, readsOnDevice: Bool, in catalog: ModelCatalog?) -> Route {
        let type = classification.type
        let fallback = onDeviceFallback(for: type, fit: fit, hasAttachments: hasAttachments,
                                        readsOnDevice: readsOnDevice)
        if onDeviceTypes.contains(type), fallback == nil {
            return .onDevice(type, runnerUp: classification.runnerUp)
        }
        let (family, effort) = defaultChoice(for: type)
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

    /// Why `choice` cannot answer now, and the default does; `nil` when it can.
    ///
    /// A Claude family not in the catalog, an endpoint without a model or consent, or one offered a Domanda with
    /// Allegati, which go only to Claude or to the Mac (#101). Without a catalog, a Claude family is taken on trust.
    private static func pause(of choice: TypePreference, preferences: Preferences, hasAttachments: Bool,
                              in catalog: ModelCatalog?) -> Route.PausedPreference? {
        switch choice {
        case let .claude(step):
            guard let catalog, catalog.entry(for: step.family.alias) == nil else { return nil }
            return .notInCatalog(step.family)
        case let .endpoint(id):
            if hasAttachments { return .attachments }
            return preferences.endpoints.contains { $0.id == id } ? nil : .endpointUnavailable
        }
    }

    /// The route of `choice`, the user's preference for `type`, once `pause(of:)` found nothing in its way.
    private static func preferredRoute(of choice: TypePreference, for type: RequestType, preferences: Preferences,
                                       in catalog: ModelCatalog?) -> Route {
        switch choice {
        case let .claude(step):
            guard let entry = catalog?.entry(for: step.family.alias) else {
                return Route(family: step.family, model: step.family.alias, effort: step.effort, reason: .preferred(type))
            }
            return Route(family: step.family, model: entry.value, effort: step.effort.flatMap { effort($0, in: entry) },
                         reason: .preferred(type))
        case let .endpoint(id):
            let endpoint = preferences.endpoints.first { $0.id == id }
            return Route(family: nil, model: nil, effort: nil, reason: .preferred(type),
                         destination: endpoint.map(Route.Destination.endpoint) ?? .claude)
        }
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
