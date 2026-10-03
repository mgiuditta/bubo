import Foundation
import os

/// A Domanda typed in the HUD, answered by `claude` through the agent bridge, or by Apple Foundation Models on the Mac.
@Observable
final class QuestionModel {
    /// What the user is typing; each change asks the router for a new forecast, for the chip.
    var prompt = "" {
        didSet {
            if prompt != oldValue { updateForecast() }
        }
    }
    /// The Allegati in the prompt, dragged onto the Orb, that go with the next Domanda.
    private(set) var attachments: [Allegato] = []
    /// What the router would choose for the prompt as typed, for the chip; `nil` with an empty prompt and until the
    /// first forecast.
    private(set) var forecast: Route?
    /// The model and effort the user picked in the chip for the next Domanda; `nil` when the router chooses.
    private(set) var chipChoice: Route?
    /// The answer so far, growing as it streams.
    private(set) var answer = ""
    /// Whether an answer is on its way.
    private(set) var isAnswering = false
    /// Why the last Domanda got no answer, if it failed.
    private(set) var failure: QuestionFailure?
    /// The Quota last reported by `claude` through the bridge this model owns, or else the one saved at the last
    /// launch; empty when there is neither.
    private(set) var quota: Quota
    /// When the last prompt will be asked again, while waiting for a limit's reset.
    private(set) var resumesAt: Date?
    /// Whether `claude` runs with the API key, paid per use; only after the user's consent (ADR 0003).
    private(set) var usesAPIKey = false
    /// What the reason line under the last answer says: who answered, why, and at what cost; `nil` before the first.
    private(set) var routedAnswer: RoutedAnswer?
    /// The note the last Domanda saved in the Secondo cervello ("Ricordati questo"), if any.
    private(set) var savedNote: URL?
    /// The Sintesi parlata while Bubo says it, as subtitles; `nil` when Bubo is silent.
    private(set) var subtitle: String?
    /// Whether to invite the user to download a better voice: Bubo spoke with a basic-quality one, and the user did not
    /// close the invitation yet.
    private(set) var invitesBetterVoice = false
    /// The Modello locale Bubo proposes, once, after finding Ollama or LM Studio on the Mac; `nil` when there is
    /// nothing to propose, and after the user's answer.
    private(set) var localModelOffer: LocalModelDetector.Offer?
    /// The endpoints the user left out of "Rifai con…" for this Domanda, by not giving their consent.
    private(set) var declinedEndpoints: Set<String> = []
    /// The road every Domanda takes to `claude`, moving the Orb on the way.
    let intake: IntakePipeline
    /// The OpenAI-compatible endpoints "Rifai con…" offers, and the clouds allowed to receive Domande.
    let endpoints: EndpointSettings
    /// What the user chose with "Usa sempre per «Tipo»".
    let preferences: TypePreferences
    /// The Tipo di richiesta of the last Domanda, for "Usa sempre per «Tipo»"; `nil` when it could not be decided.
    private(set) var lastType: RequestType?
    /// The models of the user's Copilot plan, as `listModels()` lists them; empty until "Rifai con…" first reads them,
    /// and without a paid Copilot.
    private(set) var copilotModels: [CopilotModel] = []

    /// Creates a model that finds `claude` with `cli`, answers its `cerca` tool with `index` and its `ricorda` tool
    /// with `secondBrain`.
    ///
    /// - Parameters:
    ///   - orb: The Orb that thinks, morphs and works with each Domanda, and plays the Orbite when the prompt asks for it.
    ///   - intake: The pipeline the Domande go through; one driving `orb` when `nil`.
    ///   - bridgeExecutable: The agent bridge; tests pass a stand-in.
    ///   - bridgeArguments: The arguments of `bridgeExecutable`.
    ///   - defaults: Where the last Quota is kept between launches.
    ///   - apiKey: Reads the saved API key, from `APIKeyStore` when `nil`; called only after the user chose it.
    ///   - endpoints: The OpenAI-compatible endpoints and their consents.
    ///   - preferences: The user's preferences for each Tipo.
    ///   - endpointClient: The client that asks them; tests pass one served by a stand-in server.
    ///   - endpointKey: Reads an endpoint's key, from `APIKeyStore` when `nil`; called only when that endpoint answers.
    ///   - endpointContext: Reads the context of an endpoint's model, for the cap of the Allegati.
    ///   - localServers: Finds Ollama and LM Studio on the Mac, and tells whether they can answer.
    ///   - speaker: Says the Sintesi parlata of the Domande asked by voice; the voices of the Mac when `nil`.
    ///   - onDevice: Apple's model on the Mac, which `intake` measures with when it is `nil`.
    ///   - onDeviceAnswerer: Answers the Domande the router keeps on the Mac; Foundation Models on `onDevice` when `nil`.
    ///   - ledger: Where each turn's tokens and figure are recorded, in the group "Domande"; none when `nil`.
    ///   - prices: The prices the turns of other providers are estimated with.
    ///   - budgets: The Budgets the router avoids past their threshold, and the reason line warns of.
    ///   - copilot: Finds the user's `copilot` when its plan is a paid one, and `nil` otherwise (ADR 0011); called only
    ///     when the user opens "Rifai con…" or sends a Domanda to Copilot, never on its own.
    init(cli: ClaudeCLI = ClaudeCLI(), index: SearchIndex? = nil, secondBrain: SecondBrain? = nil,
         orb: OrbControls = .shared, intake: IntakePipeline? = nil,
         bridgeExecutable: URL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/bubo-agent"),
         bridgeArguments: [String] = [], defaults: UserDefaults = .standard,
         apiKey: (() async throws -> String?)? = nil, endpoints: EndpointSettings = .shared,
         preferences: TypePreferences = .shared,
         endpointClient: OpenAICompatibleClient = OpenAICompatibleClient(),
         endpointKey: ((OpenAICompatibleEndpoint) async throws -> String?)? = nil,
         endpointContext: EndpointContextReader = EndpointContextReader(),
         localServers: LocalModelDetector = LocalModelDetector(),
         speaker: (any VoiceSpeaker)? = nil,
         onDevice: OnDeviceModel = OnDeviceModel(), onDeviceAnswerer: (any OnDeviceAnswering)? = nil,
         ledger: CostLedger? = nil, prices: PriceTable = .shared, budgets: BudgetSettings = .shared,
         copilot: (() async -> URL?)? = nil) {
        quota = Quota.saved(in: defaults)
        self.defaults = defaults
        self.cli = cli
        self.index = index
        self.secondBrain = secondBrain
        self.orb = orb
        self.intake = intake ?? IntakePipeline(orb: orb, onDevice: onDevice)
        self.onDeviceAnswerer = onDeviceAnswerer ?? FoundationModelsAnswerer(model: onDevice)
        self.onDevice = onDevice
        self.ledger = ledger
        self.prices = prices
        self.budgets = budgets
        self.bridgeExecutable = bridgeExecutable
        self.bridgeArguments = bridgeArguments
        let store = APIKeyStore()
        self.apiKey = apiKey ?? { try await store.key() }
        self.endpoints = endpoints
        self.preferences = preferences
        self.endpointClient = endpointClient
        self.endpointContext = endpointContext
        self.localServers = localServers
        self.endpointKey = endpointKey ?? { try await APIKeyStore(account: $0.keychainAccount).key() }
        self.makeSpeaker = speaker.map { speaker in { speaker } } ?? { SpeechOutput() }
        self.findCopilot = copilot ?? {
            guard case .ready = await CopilotReadiness.detect() else { return nil }
            return await CopilotLocator().executableURL()
        }
    }

    /// Where the note `citation` cites opens, with Obsidian on the Mac or not; `nil` without a Secondo cervello or
    /// when the note is not in it.
    func destination(of citation: NoteCitation, hasObsidian: Bool) -> NoteDestination? {
        guard let location = secondBrain?.location, let file = citation.file(inFolder: location.url) else { return nil }
        return NoteDestination(file: file, isObsidianVault: location.isObsidianVault, hasObsidian: hasObsidian)
    }

    /// The task answering the last Domanda, or waiting to ask it again.
    @ObservationIgnored private(set) var answering: Task<Void, Never>?
    @ObservationIgnored private let cli: ClaudeCLI
    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let secondBrain: SecondBrain?
    @ObservationIgnored private let orb: OrbControls
    @ObservationIgnored private let bridgeExecutable: URL
    @ObservationIgnored private let bridgeArguments: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let apiKey: () async throws -> String?
    @ObservationIgnored private let endpointClient: OpenAICompatibleClient
    @ObservationIgnored private let endpointKey: (OpenAICompatibleEndpoint) async throws -> String?
    @ObservationIgnored private let endpointContext: EndpointContextReader
    @ObservationIgnored private let localServers: LocalModelDetector
    /// The Allegati of this Domanda the user confirmed for each endpoint, by its id: they go to it without asking again.
    @ObservationIgnored private var confirmedAttachments: [String: Set<Allegato>] = [:]
    @ObservationIgnored private let makeSpeaker: () -> any VoiceSpeaker
    /// The voice, made at the first Domanda asked by voice.
    @ObservationIgnored private lazy var speaker = makeSpeaker()
    /// The Sintesi parlata being said.
    @ObservationIgnored private(set) var speaking: Task<Void, Never>?
    @ObservationIgnored private let onDeviceAnswerer: any OnDeviceAnswering
    @ObservationIgnored private let onDevice: OnDeviceModel
    @ObservationIgnored private let ledger: CostLedger?
    @ObservationIgnored private let prices: PriceTable
    @ObservationIgnored private let budgets: BudgetSettings
    /// The Domanda in the CostLedger: one per prompt, its retries included.
    @ObservationIgnored private var question = UUID()
    /// How long the first token took, the last time each choice of "Rifai con…" answered.
    @ObservationIgnored private var firstTokens: [String: Duration] = [:]
    @ObservationIgnored private var bridge: AgentBridge?
    @ObservationIgnored private let findCopilot: () async -> URL?
    /// The user's `copilot`, once found with a paid plan.
    @ObservationIgnored private var copilot: URL?
    /// The reading of `copilotModels` under way, or done: one at a time.
    @ObservationIgnored private var readingCopilotModels: Task<Void, Never>?
    @ObservationIgnored private var lastPrompt = ""
    /// The Allegati of the last prompt, asked again with it; observed, since they decide the proposal of a Sessione.
    private var lastAttachments: [Allegato] = []
    /// The known Progetti, those with Sessioni, for the proposal of a Sessione; set at launch.
    @ObservationIgnored var knownProjects: () -> [URL] = { [] }
    /// Whether the Quota was asked for, or reported by `claude`, since launch.
    @ObservationIgnored private var hasFreshQuota = false
    /// How many times `claude` reported the Quota since launch, to tell whether a turn moved the 5-hour window.
    @ObservationIgnored private var quotaReports = 0
    /// The Claude models the account offers, read with the Quota; `nil` until then, and the router does without.
    @ObservationIgnored private var catalog: ModelCatalog?
    /// The strongest effort each family turned out to accept, when the SDK lowered the one asked for (an organization's
    /// `maxEffortLevel`): the Scala skips the steps above it from then on.
    @ObservationIgnored private var effortCaps: [ModelFamily: Effort] = [:]

    /// The task asking the router for the prompt being typed.
    @ObservationIgnored private(set) var forecasting: Task<Void, Never>?
    /// How long typing must pause before the router is asked: not once per key.
    private static let forecastDelay = Duration.milliseconds(250)

    /// What the chip in the prompt shows: the user's choice, or else the router's forecast.
    var chipRoute: Route? {
        chipChoice ?? forecast
    }

    /// Picks the next model in the chip (Tab), or the previous one (⇧Tab), for the next Domanda only.
    func chooseModel(forward: Bool) {
        let current = chipRoute ?? Route(family: nil, model: nil, effort: nil, reason: .unclassified)
        chipChoice = current.choosingModel(forward: forward, in: catalog)
    }

    /// Picks a stronger effort in the chip (⌥↑), or a weaker one (⌥↓); `false` when the model has no other level,
    /// and the key keeps its usual meaning.
    @discardableResult
    func chooseEffort(stronger: Bool) -> Bool {
        guard let route = chipRoute?.choosingEffort(stronger: stronger, in: catalog) else { return false }
        chipChoice = route
        return true
    }

    /// Hands the next Domanda back to the router (Esc); `false` when the router already chooses.
    @discardableResult
    func returnToRouter() -> Bool {
        guard chipChoice != nil else { return false }
        chipChoice = nil
        return true
    }

    /// Asks the router again for the prompt, once typing pauses; the chip goes away with an empty prompt, and with it
    /// the user's choice.
    private func updateForecast() {
        forecasting?.cancel()
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            forecast = nil
            chipChoice = nil
            return
        }
        forecasting = Task {
            try? await Task.sleep(for: Self.forecastDelay)
            guard !Task.isCancelled else { return }
            let route = await intake.forecastRoute(for: Richiesta(text: text, attachments: attachments),
                                                   catalog: catalog, preferences: await routerPreferences())
            guard !Task.isCancelled else { return }
            forecast = route
        }
    }

    /// The step of the Scala above the last answer's, for "Rifai più forte"; `nil` while answering, before the first
    /// answer and at the top, where the command is off.
    ///
    /// Apple Foundation Models sits below the whole Scala: above it is the first step, Haiku.
    var strongerRoute: Route? {
        guard !isAnswering, !answer.isEmpty, let routedAnswer else { return nil }
        if let copilot = routedAnswer.route.copilotModel {
            // The Scala of a Copilot model is its own efforts, as `listModels()` lists them.
            let model = copilotModels.first { $0.id == copilot.id } ?? copilot
            let effort = routedAnswer.answeringModel?.effort ?? routedAnswer.route.effort
            return model.effort(above: effort).map { .copilot(model, effort: $0, reason: .stronger) }
        }
        let scala = Scala(catalog: catalog, effortCaps: effortCaps)
        let step = routedAnswer.route.destination == .onDevice
            ? scala.steps.first
            : routedAnswer.route.step(answeredBy: routedAnswer.answeringModel).flatMap(scala.step(above:))
        return step.map(Route.stronger)
    }

    /// The choices of "Rifai con…" near the last answer, without the endpoints the user left out for this Domanda;
    /// empty while answering and before the first Domanda.
    var retryAlternatives: [RetryAlternative] {
        guard !isAnswering, !lastPrompt.isEmpty, let routedAnswer else { return [] }
        let answeredByCopilot = routedAnswer.route.copilotModel
        let current = routedAnswer.endpoint == nil && answeredByCopilot == nil
            ? routedAnswer.route.step(answeredBy: routedAnswer.answeringModel) : nil
        // With Allegati too: picking one checks them first (`attachmentVerdict(for:)`).
        let offered = endpoints.ready.filter { !declinedEndpoints.contains($0.id) }
        // Copilot gets only the Domanda's text: the Allegati go only to Claude, the Mac, or an endpoint that confirms them.
        let copilotModels = lastAttachments.isEmpty ? copilotModels : []
        let answeredBy = routedAnswer.endpoint?.id ?? answeredByCopilot.map { RetryAlternative(target: .copilot($0)).id }
        return RetryAlternative.alternatives(around: current, on: Scala(catalog: catalog, effortCaps: effortCaps),
                                             endpoints: offered, copilotModels: copilotModels, answeredBy: answeredBy)
            .map { alternative in
                var alternative = alternative
                alternative.firstToken = firstTokens[alternative.id]
                return alternative
            }
    }

    /// Reads the models of the user's Copilot plan for "Rifai con…", once: an explicit request of the user, never a
    /// turn of the model. Without a paid `copilot` they stay empty, and the next opening tries again.
    func readCopilotModels() async {
        if let readingCopilotModels { return await readingCopilotModels.value }
        let reading = Task {
            guard let copilot = await copilotExecutable() else { return }
            do {
                copilotModels = try await readyBridge().copilotModels(of: copilot)
            } catch {
                Logger.agent.notice("Copilot models not read: \(String(describing: error), privacy: .public)")
                readingCopilotModels = nil
            }
        }
        readingCopilotModels = reading
        await reading.value
    }

    /// The user's `copilot` with a paid plan, found once; `nil` without one.
    private func copilotExecutable() async -> URL? {
        if let copilot { return copilot }
        let found = await findCopilot()
        copilot = found
        if found == nil { readingCopilotModels = nil }
        return found
    }

    /// The endpoints with a model that the user left out of "Rifai con…" for this Domanda.
    var excludedEndpoints: [OpenAICompatibleEndpoint] {
        endpoints.ready.filter { declinedEndpoints.contains($0.id) }
    }

    /// Whether picking `alternative` must first ask the user's consent: a cloud that is not Claude, never allowed.
    func needsConsent(for alternative: RetryAlternative) -> Bool {
        guard case let .endpoint(endpoint) = alternative.target else { return false }
        return !endpoint.isOnMac && !endpoints.consents.contains(endpoint.id)
    }

    /// The share of the 5-hour window used, for the router; `nil` with the API key, which has no Quota, and when the
    /// window is unknown or past its reset.
    private var fiveHourUsed: Double? {
        guard !usesAPIKey, let window = quota.fiveHour, window.resetsAt > .now else { return nil }
        return window.used
    }

    /// What the router knows of the user's preferences: a cloud endpoint takes part only with its consent; the
    /// servers on the Mac they may need, and the network, are checked now.
    private func routerPreferences() async -> ModelRouter.Preferences {
        var routed = ModelRouter.Preferences(choices: preferences.choices, endpoints: endpoints.ready.filter {
            $0.isOnMac || endpoints.consents.contains($0.id)
        })
        routed.localModel = endpoints.localModel
        // Read only when the user opened "Rifai con…": until then a Copilot preference is taken on trust.
        routed.copilotModels = copilotModels.isEmpty ? nil : copilotModels
        async let isOnline = cli.isOnline()
        var asked = Set(routed.choices.values.compactMap { choice -> String? in
            if case let .endpoint(id) = choice { id } else { nil }
        })
        if let local = routed.localModel { asked.insert(local.id) }
        for endpoint in routed.endpoints where endpoint.isOnMac && asked.contains(endpoint.id) {
            let availability = await localServers.availability(of: endpoint)
            if availability != .available { routed.localOutages[endpoint.id] = availability }
        }
        routed.isOffline = !(await isOnline)
        routed.overBudget = overBudgetProviders(among: routed.endpoints)
        routed.fiveHourUsed = fiveHourUsed
        routed.quotaThresholds = QuotaThresholds.saved(in: defaults)
        return routed
    }

    /// The providers paid per use among Claude and `endpoints` whose Budget is past its threshold: Claude only with
    /// the API key, since the subscription has no Budget.
    private func overBudgetProviders(among endpoints: [OpenAICompatibleEndpoint]) -> Set<String> {
        guard let ledger else { return [] }
        let guarded = BudgetGuard(budgets: budgets.budgets, entries: ledger.entries)
        let paid = endpoints.filter { !$0.isOnMac }.map(\.name) + (usesAPIKey ? [Budgets.claude] : [])
        return Set(paid.filter(guarded.isAvoided))
    }

    /// What a Domanda to `provider`, as the CostLedger names it, may still spend; no cap without a ledger.
    private func allowance(for provider: String) -> BudgetGuard.Allowance {
        guard let ledger else { return .unlimited }
        return BudgetGuard(budgets: budgets.budgets, entries: ledger.entries).allowance(provider: provider)
    }

    /// What a Domanda to `endpoint` may still spend: nothing counts on the Mac.
    private func allowance(for endpoint: OpenAICompatibleEndpoint) -> BudgetGuard.Allowance {
        endpoint.isOnMac ? .unlimited : allowance(for: endpoint.name)
    }

    /// The spent Budget a turn of `provider` counts in, the tightest; `nil` when none is spent.
    private func spentScope(of provider: String) -> BudgetGuard.Scope? {
        guard let ledger else { return nil }
        let status = BudgetGuard(budgets: budgets.budgets, entries: ledger.entries).tightest(provider: provider)
        return status.map(\.scope)
    }

    /// Asks the Domanda a spent Budget stopped again, past the Budget, this time only: the user confirmed it.
    func continueOverBudget() {
        guard case let .budgetExhausted(stop) = failure else { return }
        if let endpoint = stop.endpoint {
            start(lastPrompt, endpoint: endpoint, ignoringBudget: true)
        } else {
            start(lastPrompt, route: stop.route, ignoringBudget: true)
        }
    }

    /// Asks the Domanda a spent Budget stopped again with the Modello locale, on the Mac and free.
    func askLocalModelOverBudget() {
        guard case .budgetExhausted = failure, let local = endpoints.localModel else { return }
        start(lastPrompt, endpoint: local)
    }

    /// Moves the Domande and the Sessioni back to the subscription, then asks the Domanda that the Budget of Claude
    /// stopped again (ADR 0003): only on the user's choice.
    func askWithSubscriptionOverBudget() {
        guard case let .budgetExhausted(stop) = failure, stop.isClaude, usesAPIKey else { return }
        moveToSubscription()
        start(lastPrompt, route: stop.route)
    }

    /// What the reason line says of the Budgets after `usage`, a turn of `provider` the ledger already has.
    private func budgetNotice(after usage: TurnUsage, of provider: String) -> BudgetNotice? {
        guard let ledger else { return nil }
        return BudgetGuard(budgets: budgets.budgets, entries: ledger.entries).notice(after: usage, of: provider)
    }

    /// Looks for Ollama and LM Studio on the Mac, and proposes the model found, once: never again, whatever the
    /// answer, and not when a Modello locale is already set.
    func lookForLocalModel() async {
        guard !endpoints.hasOfferedLocalModel, endpoints.localModel == nil else { return }
        let servers = endpoints.endpoints.filter { $0.kind == .ollama || $0.kind == .lmStudio }
        guard let offer = await localServers.offer(among: servers), !endpoints.hasOfferedLocalModel else { return }
        endpoints.markLocalModelOffered()
        localModelOffer = offer
    }

    /// Makes the proposed model the Modello locale, and the user's preference for Fatto breve and Riassunto.
    func acceptLocalModel() {
        guard let offer = localModelOffer else { return }
        var endpoint = endpoints.endpoints.first { $0.id == offer.endpoint.id } ?? offer.endpoint
        endpoint.model = offer.model
        endpoints.save(endpoint)
        endpoints.setLocalModel(endpoint)
        for type in [RequestType.shortFact, .summary] {
            preferences.set(.endpoint(id: endpoint.id), for: type)
        }
        localModelOffer = nil
    }

    /// Lets the proposal go: it is not made again.
    func dismissLocalModelOffer() {
        localModelOffer = nil
    }

    /// Asks the last prompt again with `alternative`, for this turn only unless `alwaysUse`: then it becomes the
    /// preference of the last Domanda's Tipo, for all the Domande.
    ///
    /// A cloud that is not Claude without the user's consent receives nothing: the client refuses before sending, and
    /// it never becomes a preference.
    func retry(with alternative: RetryAlternative, alwaysUse: Bool = false) {
        if alwaysUse, let lastType, !needsConsent(for: alternative) {
            switch alternative.target {
            case let .claude(step): preferences.set(.claude(step), for: lastType)
            case let .endpoint(endpoint): preferences.set(.endpoint(id: endpoint.id), for: lastType)
            case let .copilot(model): preferences.set(.copilot(id: model.id, name: model.name), for: lastType)
            }
        }
        switch alternative.target {
        case let .claude(step): start(lastPrompt, route: .retried(step))
        case let .endpoint(endpoint): start(lastPrompt, endpoint: endpoint)
        case let .copilot(model): start(lastPrompt, route: .copilot(model, effort: nil, reason: .retried))
        }
    }

    /// The Allegati of the last Domanda, which go with it when it is asked again.
    var askedAttachments: [Allegato] {
        lastAttachments
    }

    /// What may go to `endpoint` of the last Domanda's Allegati: its cap read from its server, and the user's
    /// confirmations so far.
    func attachmentVerdict(for endpoint: OpenAICompatibleEndpoint) async -> AttachmentPolicy.Verdict {
        let attachments = lastAttachments
        guard !attachments.isEmpty else { return .allowed }
        // A folder or an image is refused before the server is asked anything.
        if let withoutText = attachments.first(where: { $0.text == nil }) { return .onlyClaude(withoutText) }
        let contextLength = await endpointContext.contextLength(of: endpoint)
        return AttachmentPolicy.verdict(for: attachments, to: endpoint, contextLength: contextLength,
                                        confirmed: confirmedAttachments[endpoint.id] ?? [])
    }

    /// Lets `attachments` go to `endpoint` for the rest of this Domanda: the user confirmed them, one by one.
    func confirm(_ attachments: [Allegato], for endpoint: OpenAICompatibleEndpoint) {
        confirmedAttachments[endpoint.id, default: []].formUnion(attachments)
    }

    /// Asks the last prompt again with Claude, which reads every Allegato from its path: what Bubo proposes when the
    /// Allegati cannot go to another provider.
    func askClaude() {
        start(lastPrompt, route: .retried(Scala.Step(family: .sonnet, effort: .medium)))
    }

    /// Remembers that the user did not allow `endpoint`: it leaves "Rifai con…" until the next Domanda.
    func decline(_ endpoint: OpenAICompatibleEndpoint) {
        declinedEndpoints.insert(endpoint.id)
    }

    /// Asks the typed or dictated prompt, replacing any answer in progress; the Orbite's word plays it instead.
    func ask() {
        ask(speaksAnswer: false)
    }

    /// Asks the prompt said with push-to-talk, like `ask()`, and says the Sintesi parlata of the answer.
    func askByVoice() {
        ask(speaksAnswer: true)
    }

    /// Predicts Tipo and Variante of `text`, heard so far with push-to-talk, with the Allegati in the prompt: at the
    /// release, the Morph starts at once if the final text confirms it.
    func predict(_ text: String) {
        intake.predict(Richiesta(text: text, attachments: attachments))
    }

    /// Hides the invitation to download a better voice, for good.
    func dismissBetterVoice() {
        invitesBetterVoice = false
        defaults.set(true, forKey: Self.betterVoiceDismissedKey)
    }

    private static let betterVoiceDismissedKey = "voice.betterVoiceDismissed"

    /// Asks `text` with `attachments`, from outside the HUD, replacing any answer in progress; what is typed in the
    /// prompt stays there.
    ///
    /// The Allegati go only to Claude or to the model on the Mac, as their content.
    func ask(_ text: String, attachments: [Allegato]) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastPrompt = text
        lastAttachments = attachments
        confirmedAttachments = [:]
        declinedEndpoints = []
        question = UUID()
        start(text)
    }

    private func ask(speaksAnswer: Bool) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Push-to-talk shows no chip, so only a typed or dictated prompt takes the user's choice.
        let choice = speaksAnswer ? nil : chipChoice
        prompt = ""
        // No Domanda, no token: the Orb plays the Orbite and the last answer stays.
        if Orbite.isPlayed(by: text) {
            orb.playOrbite()
            return
        }
        lastPrompt = text
        lastAttachments = attachments
        attachments = []
        confirmedAttachments = [:]
        declinedEndpoints = []
        question = UUID()
        start(text, route: choice, speaksAnswer: speaksAnswer)
    }

    /// Puts `new` in the prompt, after the Allegati already there, and shows the Orb in Ascolto: the user writes or
    /// speaks, then sends.
    func attach(_ new: [Allegato]) {
        attachments += new.filter { !attachments.contains($0) }
        guard !attachments.isEmpty else { return }
        awaitAttachments()
        updateForecast()
    }

    /// Takes `allegato` out of the prompt; with the last one goes the Ascolto.
    func detach(_ allegato: Allegato) {
        attachments.removeAll { $0 == allegato }
        if attachments.isEmpty { stopAwaitingAttachments() }
        updateForecast()
    }

    /// Shows the Orb in Ascolto, waiting for what the user writes or says about an Allegato; nothing while a Domanda
    /// is under way.
    func awaitAttachments() {
        if orb.questionState == nil { orb.questionState = .listening }
    }

    /// Ends the Ascolto of ``awaitAttachments()``: the drag left the Orb, or the prompt was put away.
    func stopAwaitingAttachments() {
        if orb.questionState == .listening { orb.questionState = nil }
    }

    /// Asks the last prompt again.
    func retry() {
        start(lastPrompt)
    }

    /// Asks the last prompt again with `model`, a `claude` alias such as `sonnet`, instead of the router's choice.
    func retry(model: String) {
        start(lastPrompt, route: .chosen(model))
    }

    /// Asks the last prompt again one step up the Scala, for this turn only: the router's default does not change.
    func retryStronger() {
        guard let strongerRoute else { return }
        start(lastPrompt, route: strongerRoute)
    }

    /// Stops the answer in progress, keeping what arrived, or stops waiting for a reset.
    func stop() {
        answering?.cancel()
        stopSpeaking()
        resumesAt = nil
    }

    /// Stops the Sintesi parlata being said, if any, with the audio stopped before it returns: the Orb leaves Parla, and
    /// a Morph already started still runs to its end (spec 08).
    func stopSpeaking() {
        guard let speaking else { return }
        speaker.stop()
        speaking.cancel()
        self.speaking = nil
        subtitle = nil
    }

    /// The Sessione the Allegati propose: those in the prompt, or else those of the last Domanda (spec 09).
    var sessionProposal: SessionProposal? {
        SessionProposal(for: attachments.isEmpty ? lastAttachments : attachments, projects: knownProjects())
    }

    /// Accepts `proposal`: stops the Domanda and hands it to a new Sessione on the proposed Progetto, with the files
    /// of the Allegati inside it; the Allegati leave the prompt.
    func turnIntoSession(accepting proposal: SessionProposal) -> SessionDraft {
        let files = (attachments.isEmpty ? lastAttachments : attachments).compactMap(\.path)
        var draft = turnIntoSession()
        draft.project = proposal.project
        if case .session = proposal { draft.files = files }
        attachments = []
        stopAwaitingAttachments()
        updateForecast()
        return draft
    }

    /// Stops the Domanda and hands it to a new Sessione: what is typed, and the last prompt with what arrived of its
    /// answer; with no answer, what is typed or else the last prompt.
    func turnIntoSession() -> SessionDraft {
        stop()
        let typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return SessionDraft(prompt: typed.isEmpty ? lastPrompt : typed) }
        return SessionDraft(prompt: typed, question: lastPrompt, answer: answer)
    }

    /// Waits until the limit that stopped the last Domanda resets, then asks it again.
    func resumeAfterReset() {
        guard case let .bridge(.limitReached(limit)) = failure, let resetsAt = limit.resetsAt else { return }
        answering?.cancel()
        resumesAt = resetsAt
        answering = Task {
            // A few seconds past the reset, so the window has surely started again; the wait runs on through sleep.
            try? await Task.sleep(for: .seconds(max(0, resetsAt.timeIntervalSinceNow) + 5))
            guard !Task.isCancelled else { return }
            resumesAt = nil
            start(lastPrompt)
        }
    }

    /// Moves the Domande and the Sessioni to the API key until Bubo quits, then asks the last prompt again.
    ///
    /// Called only when the user confirms (ADR 0003): Bubo never moves to the API key on its own.
    func useAPIKey() async {
        do {
            guard try await apiKey() != nil else {
                failure = .apiKeyMissing
                return
            }
        } catch {
            Logger.agent.error("API key not read: \(String(describing: error), privacy: .public)")
            failure = .unexpected
            return
        }
        moveToAPIKey()
        start(lastPrompt)
    }

    /// Moves the Domande and the Sessioni to the saved API key until Bubo quits, asking nothing again.
    ///
    /// Called only when the user chooses it (ADR 0003).
    func moveToAPIKey() {
        moveCredential(toAPIKey: true)
    }

    /// Moves the Domande and the Sessioni back to the login of `claude`, after a refused API key.
    func moveToSubscription() {
        moveCredential(toAPIKey: false)
    }

    private func moveCredential(toAPIKey: Bool) {
        usesAPIKey = toAPIKey
        // Conversations in progress end on the old bridge; the next one starts with the new credential.
        bridge?.closeWhenIdle()
        bridge = nil
    }

    /// Reads the Quota without a Domanda, unless it was read or reported since launch; with no answer the saved one
    /// stays.
    ///
    /// It starts a `claude`, so never at launch (spec 25): only when the user opens the HUD. After that the Domande and
    /// the Sessioni keep it fresh.
    func readQuotaIfNeeded() async {
        guard !hasFreshQuota else { return }
        hasFreshQuota = true
        do {
            try await readyBridge().readQuota()
        } catch {
            Logger.agent.notice("Quota not read: \(String(describing: error), privacy: .public)")
        }
    }

    /// - Parameters:
    ///   - route: The user's choice for this turn; `nil` for the router's.
    ///   - endpoint: The OpenAI-compatible endpoint that answers instead of `claude`, picked in "Rifai con…".
    ///   - speaksAnswer: Whether the Domanda was asked by voice, and Bubo says the Sintesi parlata of the answer.
    ///   - ignoringBudget: Whether the Domanda goes even with a Budget spent: the user chose Continua solo questa volta.
    private func start(_ text: String, route: Route? = nil, endpoint: OpenAICompatibleEndpoint? = nil,
                       speaksAnswer: Bool = false, ignoringBudget: Bool = false) {
        answering?.cancel()
        stopSpeaking()
        answer = ""
        failure = nil
        resumesAt = nil
        savedNote = nil
        routedAnswer = nil
        isAnswering = true
        let attachments = lastAttachments
        answering = Task {
            if let endpoint {
                await stream(text, attachments: attachments, from: endpoint, ignoringBudget: ignoringBudget)
            } else {
                await stream(Richiesta(text: text, attachments: attachments), route: route, speaksAnswer: speaksAnswer,
                             ignoringBudget: ignoringBudget)
            }
        }
    }

    /// Streams `endpoint`'s answer, picked in "Rifai con…": the Domanda's text, and the text of its Allegati when they
    /// fit the endpoint's cap and the user confirmed them, straight from the Mac.
    private func stream(_ text: String, attachments: [Allegato], from endpoint: OpenAICompatibleEndpoint,
                        ignoringBudget: Bool) async {
        defer { isAnswering = false }
        // An explicit choice too: at 100% it asks first (spec 18).
        if !ignoringBudget, case let .exhausted(scope) = allowance(for: endpoint) {
            failure = .budgetExhausted(QuestionBudgetStop(scope: scope, route: .retriedElsewhere, endpoint: endpoint))
            return
        }
        // Not a byte of an Allegato leaves without its confirmation, nor is any of it cut to fit.
        guard await attachmentVerdict(for: endpoint) == .allowed else {
            failure = .attachmentsHeld
            return
        }
        guard !Task.isCancelled else { return }
        // No preference: the Orb takes the Tinta of the endpoint the user picked, whatever the router would choose.
        let submission = await intake.submit(Richiesta(text: text), to: endpoint.provider, catalog: catalog)
        defer { intake.finish(submission) }
        lastType = submission.classification?.type
        guard !Task.isCancelled else { return }
        await answer(AttachmentPolicy.prompt(text, attachments: attachments), from: endpoint, route: .retriedElsewhere,
                     submission: submission, speaksAnswer: false)
    }

    /// Streams `endpoint`'s answer to `text` for `submission`, the reason line saying `route`.
    ///
    /// - Parameter speaksAnswer: Whether the Domanda was asked by voice, and Bubo says the Sintesi parlata.
    private func answer(_ text: String, from endpoint: OpenAICompatibleEndpoint, route: Route,
                        submission: IntakePipeline.Submission, speaksAnswer: Bool) async {
        var routedAnswer = RoutedAnswer(route: route, provider: endpoint.provider, endpoint: endpoint)
        routedAnswer.answeringModel = AnsweringModel(model: endpoint.model, effort: nil)
        self.routedAnswer = routedAnswer
        let start = ContinuousClock.now
        var waitingForFirstToken = true
        let turn = UUID().uuidString, question = question
        let asked = speaksAnswer ? text + SpokenSummary.instruction : text
        var summary = speaksAnswer ? SpokenSummary() : nil
        var firstAudio: OSSignpostIntervalState?
        do {
            // The key is read only now that this endpoint answers, and goes only into its request.
            let key = try await endpointKey(endpoint)
            for try await event in endpointClient.answer(asked, from: endpoint, consents: endpoints.consents, key: key) {
                switch event {
                case let .text(chunk):
                    if waitingForFirstToken {
                        waitingForFirstToken = false
                        firstTokens[RetryAlternative(target: .endpoint(endpoint)).id] = ContinuousClock.now - start
                        intake.beginWorking(on: submission)
                        if speaksAnswer { firstAudio = Signposts.beginInterval(.voiceFirstAudio) }
                    }
                    answer += summary?.read(chunk) ?? chunk
                    if let line = summary?.line {
                        summary = nil
                        say(line, for: submission, firstAudio: firstAudio)
                    }
                case let .usage(usage):
                    self.routedAnswer?.endpointTokens = usage.input + usage.output
                    let reading = UsageReader.turn(usage, from: endpoint, prices: prices.snapshot)
                    self.routedAnswer?.usage = reading
                    ledger?.record(reading, turn: turn, question: question, provider: endpoint.name)
                    self.routedAnswer?.budgetNotice = budgetNotice(after: reading, of: endpoint.name)
                }
            }
            if var summary {
                answer += summary.finish()
                if let line = summary.line { say(line, for: submission, firstAudio: firstAudio) }
            }
        } catch is CancellationError {
        } catch let error as OpenAICompatibleError {
            Logger.agent.error("Endpoint \(endpoint.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            failure = .endpoint(error)
        } catch {
            Logger.agent.error("Endpoint key not read: \(String(describing: error), privacy: .public)")
            failure = .unexpected
        }
    }

    private func stream(_ richiesta: Richiesta, route chosen: Route?, speaksAnswer: Bool, ignoringBudget: Bool) async {
        defer { isAnswering = false }
        let signpostID = Signposts.signposter.makeSignpostID()
        var waitingForFirstToken: OSSignpostIntervalState? =
            Signposts.signposter.beginInterval("Domanda, primo token", id: signpostID)
        defer { waitingForFirstToken.map { Signposts.signposter.endInterval("Domanda, primo token", $0) } }
        // Anthropic's Tinta while the router decides; a Domanda it keeps on the Mac takes the neutral one.
        let text = richiesta.text
        // The user's choice for this turn goes before any preference.
        let submission = await intake.submit(richiesta, to: .anthropic, catalog: catalog,
                                             preferences: chosen == nil ? await routerPreferences() : .none)
        defer { intake.finish(submission) }
        lastType = submission.classification?.type
        var route = chosen ?? submission.route
        if let copilot = route.copilotModel {
            guard !Task.isCancelled else { return }
            // The Tinta of the model's vendor, whatever the router would choose (ADR 0011).
            intake.answer(submission, movedTo: copilot.provider)
            await answer(richiesta, withCopilot: copilot, route: route, submission: submission,
                         speaksAnswer: speaksAnswer, ignoringBudget: ignoringBudget)
            return
        }
        if let endpoint = route.endpoint {
            guard !Task.isCancelled else { return }
            // Neither the router nor a choice sends to a provider at 100% without asking (spec 18).
            if !ignoringBudget, case let .exhausted(scope) = allowance(for: endpoint) {
                failure = .budgetExhausted(QuestionBudgetStop(scope: scope, route: route))
                return
            }
            await answer(text, from: endpoint, route: route, submission: submission, speaksAnswer: speaksAnswer)
            return
        }
        // Asked by voice, the model writes the Sintesi parlata first, so that the voice starts with the answer.
        let asked = speaksAnswer ? text + SpokenSummary.instruction : text
        if route.destination == .onDevice {
            guard !Task.isCancelled else { return }
            routedAnswer = RoutedAnswer(route: route, provider: nil)
            do {
                var summary = speaksAnswer ? SpokenSummary() : nil
                var firstAudio: OSSignpostIntervalState?
                for try await chunk in onDeviceAnswerer.answer(to: asked, attachments: richiesta.attachments) {
                    if let state = waitingForFirstToken {
                        Signposts.signposter.endInterval("Domanda, primo token", state)
                        waitingForFirstToken = nil
                        intake.beginWorking(on: submission)
                        if speaksAnswer { firstAudio = Signposts.beginInterval(.voiceFirstAudio) }
                    }
                    answer += summary?.read(chunk) ?? chunk
                    if let line = summary?.line {
                        summary = nil
                        say(line, for: submission, firstAudio: firstAudio)
                    }
                }
                if var summary {
                    answer += summary.finish()
                    if let line = summary.line { say(line, for: submission, firstAudio: firstAudio) }
                }
                Logger.agent.info("Domanda answered on the Mac")
                // Counted after the answer, off its way: the line does not wait for it.
                let read = ([asked] + richiesta.attachments.compactMap(\.text)).joined(separator: "\n\n")
                Task { [answer, question] in await recordOnDevice(read: read, answer: answer, question: question) }
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // After the first token the answer is under way: a failure stays a failure.
                guard waitingForFirstToken != nil else {
                    Logger.agent.error("Apple FM failed mid-answer: \(String(describing: error), privacy: .public)")
                    failure = .unexpected
                    return
                }
                // Before it, once, Haiku answers instead and the reason line says why.
                Logger.agent.notice("Apple FM failed, Haiku answers: \(String(describing: error), privacy: .public)")
                route = Route(family: .haiku, model: ModelFamily.haiku.alias, effort: nil, reason: route.reason,
                              onDeviceFallback: .failed)
                intake.answer(submission, movedTo: .anthropic)
            }
        }
        // Claude with the API key gets the shared residue as its cap; spent, nothing is sent.
        var maxBudget: Decimal?
        if usesAPIKey, !ignoringBudget {
            switch allowance(for: Budgets.claude) {
            case .unlimited: break
            case let .upTo(residue): maxBudget = residue
            case let .exhausted(scope):
                failure = .budgetExhausted(QuestionBudgetStop(scope: scope, route: route))
                return
            }
        }
        let started = ContinuousClock.now
        let windowBefore = quotaReports > 0 ? quota.fiveHour : nil
        let reportsBefore = quotaReports
        // A Domanda replaced while it was classified leaves the line to the newer one.
        if !Task.isCancelled { routedAnswer = RoutedAnswer(route: route, provider: .anthropic) }
        let turn = UUID().uuidString, question = question
        defer {
            // Only a window `claude` reported both before and during the turn says what the turn used.
            if !Task.isCancelled, quotaReports > reportsBefore {
                routedAnswer?.fiveHourShare = RoutedAnswer.fiveHourShare(from: windowBefore, to: quota.fiveHour)
            }
        }
        do {
            let bridge = try await readyBridge()
            // The Varianti the agent may give the Orb at work: the ones near the Richiesta's Categoria first.
            let rosa = Catalogo.bundled?.rosa(around: submission.classification?.categoria) ?? []
            let prompt = Self.prompt(asked, attachments: richiesta.attachments)
            let stream = bridge.ask(prompt, in: try Self.directory(), model: route.model, effort: route.effort,
                                    remembers: true, rosa: rosa,
                                    readableDirectories: Self.readableDirectories(for: richiesta.attachments),
                                    maxBudget: maxBudget,
                                    progress: { [orb] progress in
                                        if case let .variante(nome) = progress { orb.showWork(nome) }
                                    },
                                    usage: { [weak self] usage in
                                        guard let self else { return }
                                        routedAnswer?.usage = usage
                                        ledger?.record(usage, turn: turn, question: question,
                                                       provider: Budgets.claude)
                                        routedAnswer?.budgetNotice = budgetNotice(after: usage, of: Budgets.claude)
                                    },
                                    answeredBy: { [weak self] in
                                        self?.routedAnswer?.answeringModel = $0
                                        self?.learnEffortCap(asked: route, answeredBy: $0)
                                    })
            var summary = speaksAnswer ? SpokenSummary() : nil
            var firstAudio: OSSignpostIntervalState?
            for try await chunk in stream {
                if let state = waitingForFirstToken {
                    Signposts.signposter.endInterval("Domanda, primo token", state)
                    waitingForFirstToken = nil
                    if let step = route.step(answeredBy: nil) {
                        firstTokens[RetryAlternative(target: .claude(step)).id] = ContinuousClock.now - started
                    }
                    intake.beginWorking(on: submission)
                    if speaksAnswer { firstAudio = Signposts.beginInterval(.voiceFirstAudio) }
                }
                answer += summary?.read(chunk) ?? chunk
                if let line = summary?.line {
                    summary = nil
                    say(line, for: submission, firstAudio: firstAudio)
                }
            }
            if var summary {
                answer += summary.finish()
                if let line = summary.line { say(line, for: submission, firstAudio: firstAudio) }
            }
        } catch is CancellationError {
        } catch let failure as QuestionFailure {
            self.failure = failure
        } catch let error as AgentBridgeError {
            Logger.agent.error("Domanda failed: \(String(describing: error), privacy: .public)")
            // With no network `claude` gives up with a generic error: say why instead.
            if case .failed = error, !(await cli.isOnline()) {
                failure = .offline
            } else if error == .budgetExhausted {
                failure = .budgetExhausted(QuestionBudgetStop(scope: spentScope(of: Budgets.claude) ?? .provider(Budgets.claude),
                                                              route: route))
            } else {
                failure = .bridge(error)
            }
        } catch {
            Logger.agent.error("Domanda failed: \(error)")
            failure = .unexpected
        }
    }

    /// Streams the answer of `model`, a Copilot model the user picked or prefers, through the user's `copilot`: the
    /// Domanda's text only, in a session without tools.
    ///
    /// - Parameter speaksAnswer: Whether the Domanda was asked by voice, and Bubo says the Sintesi parlata.
    private func answer(_ richiesta: Richiesta, withCopilot model: CopilotModel, route: Route,
                        submission: IntakePipeline.Submission, speaksAnswer: Bool, ignoringBudget: Bool) async {
        // Not a byte of an Allegato goes to Copilot.
        guard richiesta.attachments.isEmpty else {
            failure = .attachmentsHeld
            return
        }
        if !ignoringBudget, case let .exhausted(scope) = allowance(for: Budgets.copilot) {
            failure = .budgetExhausted(QuestionBudgetStop(scope: scope, route: route))
            return
        }
        guard let copilot = await copilotExecutable() else {
            failure = .copilotUnavailable
            return
        }
        guard !Task.isCancelled else { return }
        routedAnswer = RoutedAnswer(route: route, provider: model.provider)
        let started = ContinuousClock.now
        var waitingForFirstToken = true
        let turn = UUID().uuidString, question = question
        let asked = speaksAnswer ? richiesta.text + SpokenSummary.instruction : richiesta.text
        var summary = speaksAnswer ? SpokenSummary() : nil
        var firstAudio: OSSignpostIntervalState?
        do {
            let stream = try await readyBridge().askCopilotQuestion(
                asked, copilot: copilot, model: model.id, effort: route.effort,
                usage: { [weak self] usage in
                    guard let self else { return }
                    // The Spesa estimated on GitHub's list prices, the same in the line and in the ledger.
                    let spesa = CopilotPriceTable.bundled?.spesa(of: usage) ?? usage
                    routedAnswer?.usage = spesa
                    ledger?.record(spesa, turn: turn, question: question, provider: Budgets.copilot)
                    routedAnswer?.budgetNotice = budgetNotice(after: spesa, of: Budgets.copilot)
                },
                answeredBy: { [weak self] in self?.routedAnswer?.answeringModel = $0 })
            for try await chunk in stream {
                if waitingForFirstToken {
                    waitingForFirstToken = false
                    firstTokens[RetryAlternative(target: .copilot(model)).id] = ContinuousClock.now - started
                    intake.beginWorking(on: submission)
                    if speaksAnswer { firstAudio = Signposts.beginInterval(.voiceFirstAudio) }
                }
                answer += summary?.read(chunk) ?? chunk
                if let line = summary?.line {
                    summary = nil
                    say(line, for: submission, firstAudio: firstAudio)
                }
            }
            if var summary {
                answer += summary.finish()
                if let line = summary.line { say(line, for: submission, firstAudio: firstAudio) }
            }
        } catch is CancellationError {
        } catch let failure as QuestionFailure {
            self.failure = failure
        } catch let AgentBridgeError.failed(message) {
            Logger.agent.error("Copilot failed: \(message, privacy: .public)")
            failure = .copilotFailed(message)
        } catch let error as AgentBridgeError {
            Logger.agent.error("Copilot failed: \(String(describing: error), privacy: .public)")
            failure = .bridge(error)
        } catch {
            Logger.agent.error("Copilot failed: \(String(describing: error), privacy: .public)")
            failure = .unexpected
        }
    }

    /// What `claude` reads of a Domanda: `question`, each Allegato with no file behind it under its name, then the
    /// paths of the others, which the agent reads from the disk (spec 09).
    static func prompt(_ question: String, attachments: [Allegato]) -> String {
        guard !attachments.isEmpty else { return question }
        let inline = attachments.filter { $0.path == nil }.map { "--- \($0.name) ---\n\($0.text ?? "")" }
        let paths = attachments.compactMap(\.path).map { "- \($0.path(percentEncoded: false))" }
        let onDisk = paths.isEmpty ? [] : ["Allegati da leggere dal disco:\n" + paths.joined(separator: "\n")]
        return ([question] + inline + onDisk).joined(separator: "\n\n")
    }

    /// The folders `claude` may read besides its own for `attachments`: each folder, and the folder of each file.
    static func readableDirectories(for attachments: [Allegato]) -> [URL] {
        let directories = attachments.compactMap { allegato in
            allegato.path.map { path in
                let directory = allegato.kind == .folder ? path : path.deletingLastPathComponent()
                return URL(filePath: directory.path(percentEncoded: false), directoryHint: .isDirectory)
            }
        }
        return directories.reduce(into: []) { unique, directory in
            if !unique.contains(directory) { unique.append(directory) }
        }
    }

    /// Records the turn Apple FM answered: gratis, with the tokens the model counts of what it read and wrote.
    private func recordOnDevice(read: String, answer: String, question: UUID) async {
        guard let ledger else { return }
        async let input = onDevice.tokenCount(of: read)
        async let output = onDevice.tokenCount(of: answer)
        let usage = await UsageReader.onDevice(input: input, output: output)
        ledger.record(usage, turn: UUID().uuidString, question: question, provider: "Apple FM")
    }

    /// Says `line`, the Sintesi parlata of `submission`'s answer, with the Orb in Parla and the line as subtitles.
    ///
    /// - Parameter firstAudio: The interval from the first text of the answer, which the first audio ends.
    private func say(_ line: String, for submission: IntakePipeline.Submission, firstAudio: OSSignpostIntervalState?) {
        speaking?.cancel()
        subtitle = line
        intake.beginSpeaking(on: submission)
        if speaker.hasOnlyDefaultVoices, !defaults.bool(forKey: Self.betterVoiceDismissedKey) { invitesBetterVoice = true }
        speaking = Task { [speaker, orb, intake] in
            var firstAudio = firstAudio
            await speaker.speak(line) { level in
                if let state = firstAudio {
                    Signposts.endInterval(.voiceFirstAudio, state)
                    firstAudio = nil
                }
                orb.voiceLevel = level
            }
            intake.endSpeaking(on: submission)
            if !Task.isCancelled { subtitle = nil }
        }
    }

    /// Remembers the effort the SDK lowered `asked`'s to, as the strongest its family accepts.
    private func learnEffortCap(asked route: Route, answeredBy answeringModel: AnsweringModel) {
        guard let family = route.family, ModelFamily(model: answeringModel.model) == family,
              let wanted = route.effort, let effective = answeringModel.effort, effective < wanted
        else { return }
        effortCaps[family] = min(effortCaps[family] ?? effective, effective)
    }

    /// Starts the bridge without asking anything, so the first Domanda or Sessione finds it ready.
    func startBridge() async {
        do {
            try await readyBridge().start()
        } catch {
            Logger.agent.notice("Bridge not started: \(String(describing: error), privacy: .public)")
        }
    }

    /// The bridge to `claude`, started on first use and shared with the Sessioni.
    func readyBridge() async throws -> AgentBridge {
        if let bridge { return bridge }
        guard let claude = await cli.executableURL() else { throw QuestionFailure.claudeMissing }
        // The key is read only once the user chose it, and goes only into the bridge's environment.
        let key = try await usesAPIKey ? apiKey() : nil
        // The bridge's start, the Quota read and a Domanda can all get here across the awaits: keep one bridge.
        if let bridge { return bridge }
        let bridge = AgentBridge(executable: bridgeExecutable, arguments: bridgeArguments,
                                 environment: ChildEnvironment.make(claude: claude, apiKey: key,
                                                                    conversations: try? ConversationStore.defaultFile()),
                                 quota: { [weak self] reported in
                                     guard let self else { return }
                                     hasFreshQuota = true
                                     quotaReports += 1
                                     quota = quota.merging(reported)
                                     quota.save(to: defaults)
                                 },
                                 catalog: { [weak self] in self?.catalog = $0 },
                                 remember: { [weak self] text, title in
                                     await self?.remember(text, titled: title) ?? "Bubo non è disponibile."
                                 }) { [index] query, project, source in
            await index?.toolResult(for: query, project: project, source: source) ?? "L'Indice non è disponibile."
        }
        self.bridge = bridge
        return bridge
    }

    /// Saves a note for the `ricorda` tool, and returns what the tool answers `claude`.
    func remember(_ text: String, titled title: String) async -> String {
        do {
            guard let note = try await secondBrain?.remember(text, titled: title) else {
                return "Nota non salvata: l'utente non ha scelto il Secondo cervello. Digli di sceglierlo in "
                    + "Impostazioni › Generale › Secondo cervello."
            }
            savedNote = note.file
            return "Nota salvata nel Secondo cervello: Bubo/Note/\(note.file.lastPathComponent)"
        } catch NoteWriter.Failure.unreachable {
            return "Nota non salvata: la cartella del Secondo cervello non è raggiungibile (disco scollegato o "
                + "cartella spostata)."
        } catch {
            Logger.index.error("Note not saved: \(error)")
            return "Nota non salvata: Bubo non è riuscito a scriverla."
        }
    }

    /// Where Domande run: they have no Progetto, so an empty folder of Bubo's own.
    static func directory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Bubo/Domande", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
