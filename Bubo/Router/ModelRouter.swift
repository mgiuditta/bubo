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
        /// The Modello locale the user set, which answers without a network; `nil` without one.
        var localModel: OpenAICompatibleEndpoint?
        /// The servers on the Mac, by endpoint id, found unable to answer just now; one not here is taken on trust.
        var localOutages: [String: LocalModelDetector.Availability] = [:]
        /// Whether the Mac has no network: the Domande go to the Modello locale, or else to Apple Foundation Models.
        var isOffline = false
        /// The providers paid per use whose Budget is past its threshold, as the CostLedger names them ("Anthropic"
        /// only with the API key): the router avoids them when it has an alternative (spec 18).
        var overBudget: Set<String> = []
        /// The share of the 5-hour window used, from 0 to 1; `nil` when unknown: with the API key, never reported,
        /// or past its reset. Unknown, the Quota changes nothing.
        var fiveHourUsed: Double?
        /// Past which share of the 5-hour window the router saves the Quota.
        var quotaThresholds = QuotaThresholds()

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
        let route = routeBeforeBudgets(for: classification, fit: fit, hasAttachments: hasAttachments,
                                       readsOnDevice: readsOnDevice, preferences: preferences, in: catalog)
        guard let classification, let provider = Self.paidProvider(of: route),
              preferences.overBudget.contains(provider) else { return route }
        return Self.alternative(to: route, avoiding: provider, for: classification, fit: fit,
                                hasAttachments: hasAttachments, readsOnDevice: readsOnDevice,
                                preferences: preferences, in: catalog) ?? route
    }

    /// The route of `classification` before the Budgets, which `route(for:fit:hasAttachments:readsOnDevice:preferences:in:)`
    /// then reads.
    private func routeBeforeBudgets(for classification: RequestClassification?, fit: OnDeviceFit,
                                    hasAttachments: Bool, readsOnDevice: Bool, preferences: Preferences,
                                    in catalog: ModelCatalog?) -> Route {
        guard let classification else { return Route(family: nil, model: nil, effort: nil, reason: .unclassified) }
        let type = classification.type
        if preferences.isOffline,
           let route = Self.offlineRoute(for: type, fit: fit, hasAttachments: hasAttachments,
                                         readsOnDevice: readsOnDevice, preferences: preferences) {
            return route
        }
        guard let choice = preferences.choices[type] else {
            let route = Self.defaultRoute(for: classification, fit: fit, hasAttachments: hasAttachments,
                                          readsOnDevice: readsOnDevice, in: catalog)
            return Self.savingQuota(route, for: type, fit: fit, hasAttachments: hasAttachments,
                                    readsOnDevice: readsOnDevice, preferences: preferences, in: catalog)
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

    /// Who is paid for `route`, as the CostLedger names it; `nil` for a model on the Mac, which is free.
    static func paidProvider(of route: Route) -> String? {
        switch route.destination {
        case .claude: Budgets.claude
        case .onDevice: nil
        case let .endpoint(endpoint): endpoint.isOnMac ? nil : endpoint.name
        }
    }

    /// Another route for `route`, whose provider's Budget is past its threshold: the Tipo's default for a preference,
    /// or else the Modello locale; `nil` when there is none and `route` stays, with the warning only.
    private static func alternative(to route: Route, avoiding provider: String,
                                    for classification: RequestClassification, fit: OnDeviceFit,
                                    hasAttachments: Bool, readsOnDevice: Bool, preferences: Preferences,
                                    in catalog: ModelCatalog?) -> Route? {
        if case .preferred = route.reason {
            var fallback = defaultRoute(for: classification, fit: fit, hasAttachments: hasAttachments,
                                        readsOnDevice: readsOnDevice, in: catalog)
            if paidProvider(of: fallback).map(preferences.overBudget.contains) != true {
                fallback.pausedPreference = .overBudget(provider)
                return fallback
            }
        }
        // The Allegati go only to Claude or to Apple FM (#101).
        guard let local = preferences.localModel, !hasAttachments,
              preferences.localOutages[local.id] ?? .available == .available else { return nil }
        var fallback = Route(family: nil, model: nil, effort: nil,
                             reason: .type(classification.type, runnerUp: classification.runnerUp),
                             destination: .endpoint(local))
        fallback.avoidedBudget = provider
        return fallback
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
            guard let endpoint = preferences.endpoints.first(where: { $0.id == id }) else { return .endpointUnavailable }
            switch preferences.localOutages[id] {
            case .serverOff?: return .localServerOff(endpoint.name)
            case .modelMissing?: return .localModelMissing(endpoint.name)
            case .available?, nil: return nil
            }
        }
    }

    /// `route`, the automatic choice for `type`, once the Quota is seen (spec 10): past `QuotaThresholds.onMac` the
    /// Modello locale or Apple Foundation Models, as without a network; past `QuotaThresholds.stepDown`, or when
    /// neither can answer, one step down the Scala. Never a block: at the bottom of the Scala `route` stays.
    private static func savingQuota(_ route: Route, for type: RequestType, fit: OnDeviceFit, hasAttachments: Bool,
                                    readsOnDevice: Bool, preferences: Preferences,
                                    in catalog: ModelCatalog?) -> Route {
        guard let used = preferences.fiveHourUsed, route.destination == .claude else { return route }
        let thresholds = preferences.quotaThresholds
        if used > thresholds.onMac,
           let onMac = offlineRoute(for: type, fit: fit, hasAttachments: hasAttachments, readsOnDevice: readsOnDevice,
                                    preferences: preferences) {
            return Route(family: nil, model: nil, effort: nil, reason: .quota(type, threshold: thresholds.onMac),
                         destination: onMac.destination)
        }
        guard used > thresholds.stepDown, let family = route.family,
              let lower = Scala(catalog: catalog).step(below: Scala.Step(family: family, effort: route.effort))
        else { return route }
        return Route(family: lower.family, model: catalog?.entry(for: lower.family.alias)?.value ?? lower.family.alias,
                     effort: lower.effort, reason: .quota(type, threshold: thresholds.stepDown),
                     onDeviceFallback: route.onDeviceFallback)
    }

    /// Who answers `type` without a network: the Modello locale when it answers and nothing leaves the Mac with it,
    /// or else Apple Foundation Models when the Domanda fits; `nil` when neither can, and the usual route goes on.
    private static func offlineRoute(for type: RequestType, fit: OnDeviceFit, hasAttachments: Bool,
                                     readsOnDevice: Bool, preferences: Preferences) -> Route? {
        if let local = preferences.localModel, !hasAttachments,
           preferences.localOutages[local.id] ?? .available == .available {
            return Route(family: nil, model: nil, effort: nil, reason: .offline(type), destination: .endpoint(local))
        }
        let fitsOnDevice = switch fit {
        case .fits: true
        case .notMeasurable: !hasAttachments
        case .tooLong, .unavailable: false
        }
        guard readsOnDevice, fitsOnDevice else { return nil }
        return Route(family: nil, model: nil, effort: nil, reason: .offline(type), destination: .onDevice)
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
