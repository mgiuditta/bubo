import Foundation
import os

/// The Sessioni of every Progetto, kept in a JSON file across launches.
@Observable
final class SessionStore {
    /// The Sessioni, oldest first.
    private(set) var sessions: [Session] = []
    /// The Richieste di permesso waiting in the Sessioni, and the permissions given "Per questa Sessione".
    private(set) var permissions = RequestCenter()
    /// The agent's questions waiting in each Sessione, oldest first.
    private(set) var questions: [UUID: [AgentQuestion]] = [:]
    /// Until when each merge made by Fondi can be undone, by Sessione.
    private(set) var undoDeadlines: [UUID: Date] = [:]
    /// Whether the turn in progress of each Sessione runs in the Sandbox, from when its `claude` is asked.
    private(set) var sandboxedTurns: [UUID: Bool] = [:]
    /// What the Sandbox stopped in the latest turn of each Sessione, oldest first, one line each.
    private(set) var sandboxBlocks: [UUID: [SandboxBlock]] = [:]

    /// The most blocks kept per Sessione: the latest ones.
    static let sandboxBlockLimit = 20

    /// Called with each file the agent of a Sessione reads or writes, for the Galassia; reads change no Sessione.
    @ObservationIgnored var onFileActivity: ((UUID, AgentProgress) -> Void)?

    /// Called when a Sessione becomes Fusa with Fondi, or Archiviata with Archivia, with its new Fase: the
    /// Riassunto di Sessione starts there. The Archiviata that ends a Fusa calls nothing.
    @ObservationIgnored var onPhaseChange: ((UUID, Session.Phase) -> Void)?

    /// Annulla of a line Salvato: puts the note of the Secondo cervello back as it was before the write.
    @ObservationIgnored var undoSaved: ((BrainChange) throws -> Void)?

    /// How long Annulla merge is offered after Fondi.
    static let undoWindow = Duration.seconds(10)

    /// The Progetti that have Sessioni, most recent first.
    var projects: [URL] {
        var seen = Set<URL>()
        return sessions.reversed().map(\.project).filter { seen.insert($0).inserted }
    }

    /// Creates a store kept in `file`, preparing copies with `worktrees` and talking to `claude` through `bridge`.
    ///
    /// A Sessione that was in Lavora or Attende te when Bubo quit is Ferma and waits for Riprendi: nothing resumes
    /// on its own. One whose Progetto or worktree is gone is in Errore.
    ///
    /// - Parameters:
    ///   - orb: The Orb whose Stato follows the Attività of the Sessioni; `nil` for none.
    ///   - alerts: The notifications and the Dock badge of the Sessioni in Attende te; `nil` for none.
    ///   - ledger: Where each turn's tokens and figure are recorded.
    ///   - drafts: The Bozze that Avvia turns into Sessioni.
    ///   - sandbox: Whether each Progetto runs its Sessioni's commands in the Sandbox.
    ///   - automations: The Automazioni, whose Regole "in questa Automazione" the report of an Esecuzione adds to.
    init(file: URL, worktrees: WorktreeManager, orb: OrbControls? = nil, alerts: WaitingAlerts? = nil,
         ledger: CostLedger = CostLedger(), drafts: DraftStore = DraftStore(), sandbox: SandboxStore = SandboxStore(),
         automations: AutomationStore = AutomationStore(), bridge: @escaping () async throws -> AgentBridge) {
        self.file = file
        self.automations = automations
        self.sandbox = sandbox
        self.worktrees = worktrees
        self.ledger = ledger
        self.drafts = drafts
        self.orb = orb
        self.alerts = alerts
        self.bridge = bridge
        do {
            sessions = try JSONDecoder().decode([Session].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Logger.sessions.error("Sessioni unreadable: \(error)")
        }
        for index in sessions.indices {
            if sessions[index].isRunning {
                sessions[index].enter(.ferma)
                sessions[index].isInterrupted = true
            }
            if let failure = Self.missingFolder(of: sessions[index]) {
                sessions[index].enter(.errore)
                sessions[index].failure = failure
            }
        }
        // A merge whose Annulla Bubo's quitting cut short stays made.
        for session in sessions where session.phase == .fusa { finishMerge(session.id) }
        // Conflicts whose resolution Bubo's quitting cut short: the worktree goes back as it was.
        for session in sessions where session.resolution != nil {
            Task { await finishResolving(session.id, succeeded: false) }
        }
        servers.owners = { [weak self] in ServerAttribution.Owner.of(self?.sessions ?? []) }
        terminals.onServerHint = { [weak self] in self?.servers.notice() }
        terminals.onOpenFile = { [weak self] location, folder in self?.viewer.show(location, in: folder) }
        servers.onChange = { [weak self] servers in
            self?.previews.update(with: servers)
            self?.offerPreviews(to: servers)
        }
        // A server already listening when Bubo starts has no event of its own.
        if !ServerAttribution.Owner.of(sessions).isEmpty { servers.notice() }
    }

    /// The tokens and the figure of every turn of the Sessioni.
    @ObservationIgnored let ledger: CostLedger
    /// The Bozze, waiting for Avvia.
    @ObservationIgnored let drafts: DraftStore
    /// The Automazioni, with their Regole "in questa Automazione".
    @ObservationIgnored let automations: AutomationStore
    /// Whether each Progetto runs its Sessioni's commands in the Sandbox; a change counts from the next turn.
    @ObservationIgnored let sandbox: SandboxStore
    /// The terminals of the Sessioni, closed at Archivia, Fondi and Cancella.
    @ObservationIgnored let terminals = TerminalStore()
    /// The servers the Sessioni started, from their terminals or their agent.
    @ObservationIgnored let servers = PortWatcher()
    /// The Anteprime of the Sessioni's servers, closed with their server and at Archivia, Fondi and Cancella.
    @ObservationIgnored let previews = PreviewStore()
    /// The open pull requests of the Sessioni, read only while Bubo is in front.
    @ObservationIgnored let pullRequests = PullRequestMonitor()
    /// The visore, for the files ⌘-clicked in the terminals.
    @ObservationIgnored let viewer = CodeViewerStore()
    /// Called at each sign of life of a turn: a token, a tool at work, a permission request. The onboarding ends at the
    /// first one (spec 26).
    @ObservationIgnored var onFirstToken: () -> Void = {}
    /// What brings each turn's conversation into the Indice when it ends; `nil` without an Indice.
    @ObservationIgnored var indexer: ConversationIndexer?
    /// Called when a turn of a Sessione fails, with why; the onboarding offers a remedy for the first one (spec 26).
    @ObservationIgnored var onTurnFailure: (_ session: UUID, _ error: any Error) -> Void = { _, _ in }
    /// The Budgets each turn with the API key is capped by, read again before every turn (spec 18).
    @ObservationIgnored var budgets = BudgetSettings.shared
    /// Moves the Domande and the Sessioni back to the subscription (ADR 0003): Passa all'abbonamento at 100%.
    @ObservationIgnored var moveToSubscription: () -> Void = {}
    /// The prices of the turns' estimates while they run (#492).
    @ObservationIgnored var prices = AnthropicPriceTable.bundled
    /// The Copilot list prices its turns are estimated with; without the bundled table every turn is without a price.
    @ObservationIgnored var copilotPrices = CopilotPriceTable.bundled ?? CopilotPriceTable(date: .distantPast, models: [:])
    /// The estimate of each turn in progress, by turn, until its `result` gives the figure: it counts in the Budgets,
    /// and enters the ledger only when the turn ends without one (#492).
    @ObservationIgnored private var estimates: [String: CostLedger.Entry] = [:]
    /// The turns in progress capped by a Budget, with their Progetto: stopped as soon as the turns spend what is left.
    @ObservationIgnored private var budgetedTurns: [UUID: (provider: String, project: URL)] = [:]
    /// The turns stopped because another Sessione spent their Budget, until their end reads it.
    @ObservationIgnored private var budgetStops: Set<UUID> = []
    /// Which Sessioni have a heavy `claude`, read every 30 s while a turn is in progress (spec 25).
    @ObservationIgnored let footprints = ProcessFootprintMonitor()
    /// The turns in progress, which `restart` and `restartTurn` interrupt; not those resolving conflicts.
    @ObservationIgnored private var turnTasks: [UUID: Task<Void, Never>] = [:]
    /// The version of `claude` when it is too old to start a turn, checked before each one (spec 27); `nil` lets it
    /// start. By default nothing is checked here: the bridge still checks at `init`.
    @ObservationIgnored var outdatedClaude: () async -> String? = { nil }
    /// Where the Consegne wait in the clear, and how their branch goes (spec 24).
    @ObservationIgnored var deliveryOpener = DeliveryOpener()
    /// `~/.claude/projects`, where Avvia of a Consegna writes its conversation for `claude` to resume.
    @ObservationIgnored var claudeProjects = URL.homeDirectory.appending(path: ".claude/projects", directoryHint: .isDirectory)
    /// The user's `copilot`, for the Sessioni that run on it (ADR 0012); `nil` when there is none.
    @ObservationIgnored var locateCopilot: () async -> URL? = { await CopilotLocator().executableURL() }
    /// The clouds the user allowed: a Sessione on Copilot sends its turns only with Copilot's consent (spec 10).
    @ObservationIgnored var copilotConsents: () -> Set<String> = { EndpointSettings.shared.consents }
    /// The engine and model each Progetto's new Sessioni start on (ADR 0012).
    @ObservationIgnored var engines = ProjectEngineStore()
    /// The models of the user's Copilot plan, for the choice of model; `nil` until read, empty when `copilot` is
    /// missing or signed out, and the choice then guides to its login.
    private(set) var copilotModels: [CopilotModel]?
    /// Reads the models of the user's `copilot`; by default `listModels()` through the bridge, no turn of the model.
    @ObservationIgnored var readCopilotModels: ((URL) async throws -> [CopilotModel])?
    /// Called when a turn did not start because `claude` is too old, with its version if known.
    @ObservationIgnored var onClaudeOutdated: (_ version: String?) -> Void = { _ in }
    /// The Sessioni whose turn waits for `claude` to be updated, started again by ``startTurnsAwaitingUpdate()``.
    private(set) var awaitingClaudeUpdate: Set<UUID> = []
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let worktrees: WorktreeManager
    @ObservationIgnored private let orb: OrbControls?
    @ObservationIgnored private let alerts: WaitingAlerts?
    @ObservationIgnored private let bridge: () async throws -> AgentBridge
    /// The `claude` kept ready for the panel of the configuration, with the settings of the most recent Progetto.
    @ObservationIgnored private(set) lazy var configurationSpare = ConfigurationSpare { [weak self] in
        self?.projects.first
    } warm: { [bridge] project in
        try await bridge().warmConfiguration(for: project)
    } cool: { [bridge] in
        try await bridge().coolConfiguration()
    }
    /// Ricarica plugin for the turns in progress, once the plugins changed (spec 20).
    @ObservationIgnored private(set) lazy var pluginReloader = PluginReloader { [weak self] session, isForced in
        guard let self, let agent = turns[session], let answer = previewOffers[session]?.answer else {
            throw CancellationError()
        }
        return try await agent.reloadPlugins(ofAnswer: answer, isForced: isForced)
    } changes: { [weak self] folders in
        (self?.pluginFolders ?? .current()).changes(in: folders, includingMarketplaces: false)
    }
    /// Where Claude Code keeps the plugins, whose changes the turns in progress follow.
    @ObservationIgnored var pluginFolders = PluginFolders.current()
    @ObservationIgnored private let ports = PortAllocator()
    /// The bridge of each Sessione's turn in progress, which its Richieste di permesso are answered on.
    @ObservationIgnored private var turns: [UUID: AgentBridge] = [:]
    /// The prompt of each Sessione's turn in progress, which `restartTurn` asks again.
    @ObservationIgnored private var turnPrompts: [UUID: String] = [:]
    /// The reading of the footprints, every 30 s while a turn is in progress.
    @ObservationIgnored private var footprintWatch: Task<Void, Never>?
    /// The answer of each Sessione's turn in progress, and whether it has the Anteprima's tools.
    @ObservationIgnored private var previewOffers: [UUID: (answer: String, isOffered: Bool)] = [:]
    /// The merges that can still be undone, with the task that archives their Sessione when the time is up.
    @ObservationIgnored private var merges: [UUID: (merge: Merge, finishing: Task<Void, Never>)] = [:]
    /// The Sessioni that Fondi is merging now.
    @ObservationIgnored private var merging: Set<UUID> = []

    /// The store in Bubo's Application Support folder.
    static func makeDefault(alerts: WaitingAlerts, index: SearchIndex?, ledger: CostLedger,
                            bridge: @escaping () async throws -> AgentBridge) throws -> SessionStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let store = SessionStore(file: support.appending(path: "Bubo/Sessioni.json"), worktrees: try .makeDefault(),
                                 orb: .shared, alerts: alerts, ledger: ledger,
                                 drafts: DraftStore(file: support.appending(path: "Bubo/Bozze.json")),
                                 automations: AutomationStore(file: support.appending(path: "Bubo/Automazioni.json")),
                                 bridge: bridge)
        store.indexer = index.map { ConversationIndexer(index: $0, bridge: bridge) }
        return store
    }

    /// The configuration `claude` loads in `project`, read through the Sessioni's bridge without spending Quota.
    func configuration(of project: URL) async throws -> ClaudeConfiguration {
        try await configurationSpare.configuration(of: project) { try await bridge().configuration(of: $0) }
    }

    /// The configuration `claude` loads in `project` now, never from the `claude` kept ready: one started before an
    /// MCP login would still say the server needs it.
    func currentConfiguration(of project: URL) async throws -> ClaudeConfiguration {
        try await bridge().configuration(of: project)
    }

    /// Has every turn in progress connect again to the MCP server `name`, after a login; the next turns connect by
    /// themselves, each with a `claude` of its own.
    func reconnectMCPServer(named name: String) {
        var told = Set<ObjectIdentifier>()
        for agent in turns.values where told.insert(ObjectIdentifier(agent)).inserted {
            do {
                try agent.reconnectMCPServer(named: name)
            } catch {
                Logger.sessions.notice("MCP server not reconnected: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Logs in to the MCP server `name` of `project` with `claude mcp login`; once it succeeded, the turns in progress
    /// connect again.
    ///
    /// - Returns: The configuration of `project` read again after the login; `nil` when the login failed.
    /// - Throws: `CancellationError`, or what reading the configuration throws.
    func logIn(toMCPServer name: String, in project: URL, login: MCPLogin = .live()) async throws -> ClaudeConfiguration? {
        guard try await login.logIn(to: name, in: URL(filePath: TrustGate.root(of: project), directoryHint: .isDirectory))
        else { return nil }
        reconnectMCPServer(named: name)
        return try await currentConfiguration(of: project)
    }

    /// The Regole di permesso of `claude` in `project` that widen its Sandbox.
    func sandboxRules(of project: URL) async throws -> [SandboxWideningRule] {
        try await bridge().sandboxRules(in: project)
    }

    /// The Cronologia CLI, most recent first: the 50 most recent, or all of it when `isComplete`.
    ///
    /// The Sessioni's own conversations are never in it, even if `claude` lists them.
    func history(isComplete: Bool = false) async throws -> [CLIConversation] {
        let history = try await Signposts.measure(.cliHistory) { try await bridge().history(isComplete: isComplete) }
        let own = Set(sessions.flatMap(\.conversations))
        let theirs = history.filter { !own.contains($0.id) }
        if isComplete { lastHistory = theirs }
        return theirs
    }

    /// The Cronologia CLI as last read in full, for the Palette's titles; empty until then.
    private(set) var lastHistory: [CLIConversation] = []

    /// Copies the Cronologia CLI in Bubo's database now, then every `ConversationStore.refreshInterval`, while the
    /// user keeps it on, and brings in the Indice the conversations it is missing; until the task is cancelled.
    func keepCLIHistoryFresh() async {
        while !Task.isCancelled {
            if UserDefaults.standard.bool(forKey: ConversationStore.keepsCLIHistoryKey) {
                do {
                    let count = try await keepCLIHistory()
                    Logger.sessions.notice("Cronologia CLI copied: \(count) conversations")
                } catch {
                    Logger.sessions.error("Cronologia CLI not copied: \(String(describing: error), privacy: .private)")
                }
            }
            await indexMissingConversations()
            try? await Task.sleep(for: ConversationStore.refreshInterval)
        }
    }

    /// Brings in the Indice the conversations it is missing: the turns that ended, and the Cronologia CLI.
    private func indexMissingConversations() async {
        guard let indexer else { return }
        // A turn in progress enters the Indice when it ends.
        let turns = sessions.flatMap { session in
            (session.isRunning ? session.conversations.dropLast() : session.conversations[...]).map { ($0, session.project) }
        }
        do {
            await indexer.catchUp(turns: turns, history: try await history(isComplete: true))
        } catch {
            Logger.index.error("Cronologia CLI not indexed: \(String(describing: error), privacy: .private)")
            await indexer.catchUp(turns: turns, history: [])
        }
    }

    /// Copies in Bubo's database the Cronologia CLI not copied yet, or changed since; returns how many conversations.
    func keepCLIHistory() async throws -> Int {
        try await bridge().keepHistory()
    }

    /// Deletes the copies of the Cronologia CLI from Bubo's database; the Sessioni's stay.
    func forgetCLIHistory() async throws {
        try await bridge().forgetHistory()
    }

    /// The latest messages of a Cronologia CLI conversation, oldest first.
    func transcript(of conversation: CLIConversation) async throws -> [CLIConversation.Message] {
        try await bridge().transcript(of: conversation.id)
    }

    /// Every message of the agent's conversation `id`, oldest first, from `~/.claude` or from Bubo's copy; empty when
    /// neither has it any more.
    func transcript(ofConversation id: String) async throws -> [CLIConversation.Message] {
        try await bridge().transcript(of: id, isComplete: true)
    }

    /// Starts a Sessione titled `title` on `project`: prepares its copy on `branch`, then asks `claude` `prompt` there.
    ///
    /// - Parameters:
    ///   - onCheckout: Whether the Sessione works on the Progetto's checkout, with no copy of its own.
    ///   - conversation: The Cronologia CLI conversation the Sessione continues, as a fork.
    ///   - message: The message of `conversation` the fork stops at, included: Continua da qui. `nil` for all of it.
    ///   - issue: The issue the Sessione starts from, with ⌘I.
    ///   - choice: The engine and model of its turns; `nil` for those of `project` (ADR 0012).
    /// - Returns: The id of the new Sessione.
    /// - Throws: `SessionError.checkoutTaken` when `onCheckout` and another open Sessione already works there.
    @discardableResult
    func start(_ prompt: String, title: String, branch: String, in project: URL, onCheckout: Bool = false,
               forkingFrom conversation: CLIConversation? = nil, upTo message: String? = nil,
               issue: IssueLink? = nil, choice: EngineChoice? = nil) throws -> UUID {
        if onCheckout, let taken = checkoutSession(of: project) { throw SessionError.checkoutTaken(by: taken.title) }
        var session = Session(id: UUID(), title: title, project: project, activitySince: .now)
        session.choice = choice ?? engines.choice(for: project)
        session.prompt = prompt
        session.forkedFrom = conversation?.id
        session.forkedUpTo = conversation == nil ? nil : message
        session.continuedConversation = conversation?.id
        session.issue = issue
        if onCheckout {
            session.isOnCheckout = true
            session.workspace = Workspace(folder: project)
        }
        session.ports = ports.ports(avoiding: sessions.compactMap(\.ports))
        Signposts.signposter.withIntervalSignpost("Apertura Sessione") {
            sessions.append(session)
            save()
        }
        followActivity()
        // On the checkout a server may already listen, with no event of its own.
        if onCheckout { servers.notice() }
        turnTasks[session.id] = Task { await run(session.id, prompt: prompt, branch: branch) }
        return session.id
    }

    /// Avvia of a Bozza from a Consegna (spec 24): a worktree on its branch `consegna/…` (a new copy without one), the
    /// delivered conversation written for that worktree, then a Sessione whose first turn resumes it with this Mac's
    /// account. The content in the clear goes once written: the conversation lives in Bubo's copy like any other.
    ///
    /// - Returns: The id of the new Sessione.
    /// - Throws: `WorktreeError` when git fails, or a file error when the conversation cannot be written.
    @discardableResult
    func startDelivered(_ draft: Draft, _ delivery: DraftDelivery) async throws -> UUID {
        let workspace = if let branch = delivery.branch {
            try await worktrees.reopen(Workspace(folder: draft.project, branch: branch, base: delivery.baseCommit),
                                       of: draft.project)
        } else {
            try await worktrees.prepare(draft.project, branch: Session.proposedBranch(for: draft.title))
        }
        let folder = DeliveryOpener.folder(of: delivery.id, in: deliveryOpener.root)
        try DeliveryOpener.restore(folder, sessionID: delivery.sessionID, for: workspace.folder, in: claudeProjects)
        try? FileManager.default.removeItem(at: folder)

        let prompt = String(localized: "Questa conversazione ti arriva da \(delivery.person), che l'ha consegnata. Riprendi da dove si era fermata: in poche righe, a che punto siamo e cosa resta da fare.")
        var session = Session(id: UUID(), title: draft.title, project: draft.project, activitySince: .now)
        session.prompt = prompt
        session.workspace = workspace
        session.continuedConversation = delivery.sessionID
        session.ports = ports.ports(avoiding: sessions.compactMap(\.ports))
        sessions.append(session)
        drafts.remove(draft.id)
        save()
        followActivity()
        if let failure = await worktrees.runSetup(in: workspace, environment: session.portEnvironment) {
            update(session.id) { $0.setupFailure = failure }
        }
        turnTasks[session.id] = Task { await run(session.id, prompt: prompt, branch: workspace.branch ?? "") }
        return session.id
    }

    /// Scarta of a Bozza from a Consegna: the Bozza, the content in the clear and the branch, unless a worktree has it.
    func discardDelivered(_ draft: Draft) async {
        drafts.remove(draft.id)
        guard let delivery = draft.delivery else { return }
        await deliveryOpener.discard(delivery.id, branch: delivery.branch, in: draft.project)
    }

    /// Starts the Sessione of an Esecuzione of an Automazione, marked with `automation`, in a new copy of `project` on
    /// `branch`, and asks `claude` `prompt` there with nobody in front of it (`unattended`). Only that turn is
    /// unattended: the next ones, asked by the user, are ordinary turns without the Automazione's rules.
    ///
    /// - Parameters:
    ///   - isAutonomous: Whether the turn runs in the Modalità autonoma; it counts only in a worktree of its own.
    ///   - ended: Called once the turn ends, with whether it ended without errors.
    /// - Returns: The id of the new Sessione.
    @discardableResult
    func startExecution(_ prompt: String, title: String, branch: String, in project: URL, automation: AutomationMark,
                        unattended: UnattendedTurn, isAutonomous: Bool,
                        ended: @escaping (_ id: UUID, _ succeeded: Bool) async -> Void = { _, _ in }) -> UUID {
        var session = Session(id: UUID(), title: title, project: project, activitySince: .now)
        session.prompt = prompt
        session.automation = automation
        session.isAutonomous = isAutonomous
        session.ports = ports.ports(avoiding: sessions.compactMap(\.ports))
        sessions.append(session)
        save()
        followActivity()
        turnTasks[session.id] = Task {
            let succeeded = await run(session.id, prompt: prompt, branch: branch, unattended: unattended)
            await ended(session.id, succeeded)
        }
        return session.id
    }

    /// Asks `claude` the first prompt of the open Sessione `id` again, in its copy and in a new Conversazione, once
    /// the turn in progress, if any, is interrupted: Riprova of the onboarding (spec 26).
    func restart(_ id: UUID) {
        guard let prompt = sessions.first(where: { $0.id == id })?.prompt else { return }
        restart(id, prompt: prompt)
    }

    /// Riavvia of a Sessione pesante: interrupts the turn in progress and asks its prompt again in a new `claude`,
    /// in the same copy and in a new Conversazione that resumes the same one as the interrupted turn. Nothing when
    /// ``canRestartTurn(_:)`` is false.
    func restartTurn(_ id: UUID) {
        guard canRestartTurn(id), let prompt = turnPrompts[id] else { return }
        restart(id, prompt: prompt)
    }

    /// Whether Riavvia can start the turn in progress of the Sessione `id` again: not while it resolves conflicts.
    func canRestartTurn(_ id: UUID) -> Bool {
        turnPrompts[id] != nil && sessions.first { $0.id == id }?.resolution == nil
    }

    /// Asks `prompt` as the next turn of the open Sessione `id`, in its copy and its conversation; `false`, and
    /// nothing asked, when the Sessione cannot take a turn now (``Session/canTakeTurn``) or `prompt` is empty.
    @discardableResult
    func send(_ prompt: String, to id: UUID) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, sessions.first(where: { $0.id == id })?.canTakeTurn == true else { return false }
        restart(id, prompt: trimmed)
        return true
    }

    /// Asks `claude` `prompt` in the open Sessione `id`, once the turn in progress, if any, is interrupted.
    private func restart(_ id: UUID, prompt: String) {
        guard let session = sessions.first(where: { $0.id == id }), session.isLive else { return }
        let interrupted = turnTasks[id]
        interrupted?.cancel()
        turnTasks[id] = Task {
            // Two turns of a Sessione never run together: the interrupted one clears its state when it ends.
            await interrupted?.value
            update(id) { session in
                session.enter(.lavora)
                session.summary = nil
                session.failure = nil
                session.isInterrupted = false
            }
            await run(id, prompt: prompt, branch: session.branchToPrepare)
        }
    }

    /// Attaches `allegati` to the open Sessione `id`, after those already there: they go with its next turn
    /// (spec 09, regola "Sessione davanti"). Nothing for a Sessione that is not open.
    func attach(_ allegati: [Allegato], to id: UUID) {
        guard sessions.first(where: { $0.id == id })?.isLive == true else { return }
        update(id) { session in
            for allegato in allegati where !session.attachments.contains(allegato) {
                session.attachments.append(allegato)
            }
        }
    }

    /// Takes `allegato` off the Sessione `id`, before its next turn.
    func detach(_ allegato: Allegato, from id: UUID) {
        update(id) { $0.attachments.removeAll { $0 == allegato } }
    }

    /// The open Sessione that works on the checkout of `project`, if any.
    func checkoutSession(of project: URL) -> Session? {
        sessions.first { session in
            session.isOnCheckout && session.isLive
                && session.project.standardizedFileURL.path == project.standardizedFileURL.path
        }
    }

    /// Asks `claude` again, in the same worktree, the prompt of the turn that Bubo's quitting interrupted: in a new
    /// Conversazione that resumes the one before the interrupted turn, which never became the Sessione's.
    func resume(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.isInterrupted,
              let prompt = session.turnPrompt ?? session.prompt
        else { return }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.isInterrupted = false
        }
        turnTasks[id] = Task { await run(id, prompt: prompt, branch: session.branchToPrepare) }
    }

    /// Interrupts the turn in progress of the Sessione `id`, as Bubo's quitting would: `claude` stops, and the
    /// Sessione is Ferma with Riprendi, its worktree kept. Nothing for a Sessione at rest.
    func interrupt(_ id: UUID) {
        guard let turn = turnTasks[id], sessions.first(where: { $0.id == id })?.isRunning == true else { return }
        // Before the cancel: the end of the turn reads it.
        update(id) { $0.isInterrupted = true }
        turn.cancel()
        Task {
            await turn.value
            update(id) { session in
                session.enter(.ferma)
                session.failure = nil
                session.isInterrupted = true
            }
        }
    }

    /// Removes the worktree that an Archiviata Sessione of an Automazione still has: a crash cut its archive short.
    ///
    /// - Parameters:
    ///   - deletingBranch: Whether its branch goes too, as for an Esecuzione Senza modifiche.
    /// - Returns: Whether there was one to remove.
    @discardableResult
    func removeLeftoverWorktree(of id: UUID, deletingBranch: Bool) async -> Bool {
        guard let session = sessions.first(where: { $0.id == id }), session.automation != nil,
              session.phase == .archiviata, let workspace = session.workspace, workspace.branch != nil,
              FileManager.default.fileExists(atPath: workspace.folder.path)
        else { return false }
        await worktrees.remove(workspace, of: session.project, deletingBranch: deletingBranch)
        return true
    }

    /// Riprova on a Sessione whose turn did not start, because its Sandbox could not or `claude` was too old: the same
    /// turn again, with the Sandbox as the Progetto has it now. Nothing for any other Sessione.
    func retry(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.isLive,
              session.activity == .errore, let prompt = session.unstartedPrompt
        else { return }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.failure = nil
            session.unstartedPrompt = nil
            session.isInterrupted = false
        }
        turnTasks[id] = Task { await run(id, prompt: prompt, branch: session.branchToPrepare) }
    }

    /// Asks again the turn of the Sessione `id` that a spent Budget stopped (spec 18): within the Budgets, once raised,
    /// or past them for this turn only when `ignoringBudget`, which the user confirmed. Nothing for any other Sessione.
    func resumeAfterBudget(_ id: UUID, ignoringBudget: Bool = false) {
        guard let session = sessions.first(where: { $0.id == id }), session.isLive, session.budgetStop != nil,
              let prompt = session.unstartedPrompt
        else { return }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.failure = nil
            session.unstartedPrompt = nil
            session.isInterrupted = false
        }
        turnTasks[id] = Task {
            await run(id, prompt: prompt, branch: session.branchToPrepare, ignoringBudget: ignoringBudget)
        }
    }

    /// Moves the Domande and the Sessioni back to the subscription, then asks again the turn of the Sessione `id`
    /// that the Budget of Claude stopped: only on the user's choice (ADR 0003).
    func resumeWithSubscription(_ id: UUID) {
        guard sessions.first(where: { $0.id == id })?.budgetStop != nil else { return }
        moveToSubscription()
        resumeAfterBudget(id)
    }

    /// Starts again the turns that waited for `claude` to be updated, now that it is ready: no click needed.
    func startTurnsAwaitingUpdate() {
        let waiting = awaitingClaudeUpdate
        awaitingClaudeUpdate = []
        for id in waiting { retry(id) }
    }

    /// Riprendi on an Archiviata Sessione: Aperta again, its copy prepared again on its branch, or on a new one when
    /// Fondi deleted it, then a new turn with `prompt`. Nothing for any other Sessione, also while Fondi can be undone.
    ///
    /// - Throws: `SessionError.checkoutTaken` when the Sessione worked on the checkout and another open one works there.
    func reopen(_ id: UUID, prompt: String) throws {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .archiviata else { return }
        if session.isOnCheckout, let taken = checkoutSession(of: session.project) {
            throw SessionError.checkoutTaken(by: taken.title)
        }
        let free = ports.ports(avoiding: sessions.compactMap(\.ports))
        update(id) { session in
            // Fondi deleted the branch: the blocchi decided then are gone with it.
            if session.mergedAt != nil { session.decisions = [:] }
            session.phase = .aperta
            session.mergedAt = nil
            session.ports = free
            session.prompt = prompt
            session.workspace = session.isOnCheckout ? session.workspace : nil
            session.enter(.lavora)
            session.summary = nil
            session.failure = nil
            session.setupFailure = nil
            session.isInterrupted = false
        }
        turnTasks[id] = Task {
            await run(id, prompt: prompt, branch: session.branchToPrepare, reopening: session.workspace)
        }
    }

    /// The changes of the Sessione `id` to review, since its branch started; none while it has no copy yet.
    ///
    /// - Throws: `WorktreeError` when git fails, also outside a repo.
    func changes(of id: UUID) async throws -> [ChangedFile] {
        guard let workspace = sessions.first(where: { $0.id == id })?.workspace else { return [] }
        return try await Signposts.measure(.reviewDiff) { try await worktrees.changes(in: workspace) }
    }

    /// The lines the Sessione `id` added and removed since its branch started, for its card on the Board; `nil`
    /// when it has no copy yet or git fails.
    func lineCounts(of id: UUID) async -> (added: Int, removed: Int)? {
        guard let workspace = sessions.first(where: { $0.id == id })?.workspace,
              let hunks = try? await worktrees.changes(in: workspace).flatMap(\.hunks)
        else { return nil }
        return (hunks.reduce(0) { $0 + $1.added }, hunks.reduce(0) { $0 + $1.removed })
    }

    /// Records `decision` on the blocchi `hunks` of the Sessione `id`; `nil` makes them undecided again.
    func decide(_ decision: HunkDecision?, on hunks: [String], in id: UUID) {
        update(id) { session in
            for hunk in hunks { session.decisions[hunk] = decision }
        }
    }

    /// Sends `feedback` on the rejected blocchi to the agent, as a new turn of the Sessione `id` in its copy.
    ///
    /// The accepted blocchi among `current` stay approved; the other decisions go, since the agent changes
    /// those blocchi. Nothing while the Sessione works or is archived.
    func sendBack(_ feedback: String, to id: UUID, keepingAcceptedAmong current: [String]) {
        guard let session = sessions.first(where: { $0.id == id }), !session.isRunning, session.isLive,
              session.workspace != nil
        else { return }
        let current = Set(current)
        update(id) { session in
            session.decisions = session.decisions.filter { current.contains($0.key) && $0.value == .accepted }
            session.enter(.lavora)
            session.summary = nil
            session.failure = nil
            session.isInterrupted = false
        }
        turnTasks[id] = Task { await run(id, prompt: feedback, branch: session.branchToPrepare) }
    }

    /// What Fondi would do now with the Sessione `id`, without touching the Progetto's checkout; `nil` when the
    /// Sessione has no branch of its own or is not open.
    ///
    /// - Throws: `MergeError.detachedHead` when the checkout is not on a branch; `WorktreeError` when git fails.
    func mergePreview(of id: UUID) async throws -> MergePreview? {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta,
              let workspace = session.workspace, workspace.branch != nil
        else { return nil }
        return try await Signposts.measure(.mergePreview) {
            try await worktrees.mergePreview(of: workspace, into: session.project)
        }
    }

    /// What Fondi… on the Board would merge for the Sessione `id`: what Fondi would do now and the commit message
    /// the revisione proposes; `nil` when some blocco is not accepted yet, or the Sessione has no branch of its own,
    /// so the revisione opens instead.
    ///
    /// - Throws: `MergeError.detachedHead` when the checkout is not on a branch; `WorktreeError` when git fails.
    func boardMerge(of id: UUID) async throws -> (preview: MergePreview, message: String)? {
        let review = Review(files: try await changes(of: id))
        guard let session = sessions.first(where: { $0.id == id }), review.canMerge(with: session.decisions),
              let preview = try await mergePreview(of: id)
        else { return nil }
        return (preview, review.mergeMessage(for: session))
    }

    /// Fondi: merges the work of the Sessione `id` into the branch of its Progetto's checkout as one commit with
    /// `message`, then makes it Fusa. For `undoWindow` the merge can be undone; then the Sessione is Archiviata,
    /// its worktree and its branch go. Never pushes.
    ///
    /// - Parameter discardingRest: Whether to merge only the accepted blocchi, leaving out the others, which go
    ///   with the Sessione.
    /// - Throws: `MergeError.notAllAccepted` unless every blocco in the Sessione's changes now is accepted, or
    ///   `MergeError.noneAccepted` when `discardingRest` and none is; `MergeError` or `WorktreeError` when git
    ///   cannot merge. Nothing changes then.
    func merge(_ id: UUID, message: String, strategy: MergeStrategy, discardingRest: Bool = false) async throws {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta, !session.isRunning,
              let workspace = session.workspace, workspace.branch != nil, merging.insert(id).inserted
        else { return }
        defer { merging.remove(id) }
        // The files may have changed since the revisione was read: only what the user accepted goes in.
        let hunks = try await worktrees.changes(in: workspace).flatMap(\.hunks)
        let decisions = sessions.first { $0.id == id }?.decisions ?? [:]
        let accepted = Set(hunks.map(\.id).filter { decisions[$0] == .accepted })
        if discardingRest {
            guard !accepted.isEmpty else { throw MergeError.noneAccepted }
        } else {
            guard !hunks.isEmpty, accepted.count == hunks.count else { throw MergeError.notAllAccepted }
        }
        let merge = try await worktrees.merge(workspace, into: session.project, message: message, strategy: strategy,
                                              keepingOnly: discardingRest ? accepted : nil)
        Logger.sessions.notice("Sessione merged with \(strategy.rawValue, privacy: .public)")
        previews.close(id)
        Task { await terminals.closeAll(of: id) }
        update(id) { session in
            session.phase = .fusa
            session.mergedAt = .now
        }
        onPhaseChange?(id, .fusa)
        undoDeadlines[id] = .now + TimeInterval(Self.undoWindow.components.seconds)
        let finishing = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.finishMerge(id)
        }
        merges[id] = (merge, finishing)
    }

    /// Where Apri PR would open the pull request of the Sessione `id`, and how many of its blocchi are rejected and
    /// were not sent back to the agent; asks GitHub only the default branch, and pushes nothing.
    ///
    /// - Throws: `PullRequestError.noBranch` for a Sessione without a branch of its own; `GitHubCLIError` when `gh`
    ///   is missing, not logged in, or the Progetto has no remote on GitHub; `WorktreeError` when git fails.
    func pullRequestTarget(of id: UUID, with cli: GitHubCLI) async throws
        -> (target: PullRequestFlow.Target, rejectedCount: Int) {
        guard let session = sessions.first(where: { $0.id == id }), let workspace = session.workspace
        else { throw PullRequestError.noBranch }
        let target = try await PullRequestFlow(cli: cli, worktrees: worktrees)
            .target(of: workspace, in: session.project)
        let hunks = try await worktrees.changes(in: workspace).flatMap(\.hunks)
        let decisions = sessions.first { $0.id == id }?.decisions ?? [:]
        return (target, hunks.count { if case .rejected = decisions[$0.id] { true } else { false } })
    }

    /// What `gh pr create --dry-run` prints for the pull request of the Sessione `id`: nothing is pushed.
    ///
    /// - Throws: `GitHubCLIError`.
    func previewPullRequest(of id: UUID, _ text: PullRequestText, isDraft: Bool, to target: PullRequestFlow.Target,
                            with cli: GitHubCLI) async throws -> String {
        let issue = sessions.first { $0.id == id }?.issue
        return try await PullRequestFlow(cli: cli, worktrees: worktrees)
            .preview(text, closing: issue, isDraft: isDraft, to: target)
    }

    /// Crea PR: the work of the Sessione `id` in one commit on its branch, the branch pushed, the pull request opened
    /// into `target`, with the line that closes its issue; then the Sessione is In revisione. Only from Aperta, with
    /// the agent still.
    ///
    /// - Throws: `PullRequestError`, `GitHubCLIError` or `WorktreeError`; the Sessione stays Aperta.
    func openPullRequest(of id: UUID, _ text: PullRequestText, isDraft: Bool, to target: PullRequestFlow.Target,
                         with cli: GitHubCLI) async throws {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta, !session.isRunning,
              session.resolution == nil, let workspace = session.workspace, workspace.branch != nil,
              merging.insert(id).inserted
        else { return }
        defer { merging.remove(id) }
        let link = try await PullRequestFlow(cli: cli, worktrees: worktrees)
            .open(text, closing: session.issue, isDraft: isDraft, from: workspace, to: target)
        Logger.sessions.notice("Pull request opened: \(link.number, privacy: .public)")
        update(id) { session in
            session.phase = .inRevisione
            session.pullRequest = link
        }
    }

    /// Reads the pull requests of the Sessioni In revisione while `isForeground`, at once and then at intervals;
    /// stops otherwise. Without such Sessioni a reading runs nothing.
    func followPullRequests(isForeground: Bool) {
        pullRequests.follow(isForeground: isForeground) { [weak self] in await self?.readPullRequests() }
    }

    /// Reads once the pull request of each Sessione In revisione: a merged one makes it Fusa, then Archiviata; a
    /// closed one Aperta again; an open one keeps its checks and whether the Sessione is ahead of it.
    func readPullRequests() async {
        let open = sessions.filter { $0.phase == .inRevisione && $0.pullRequest != nil }
        pullRequests.keep(only: Set(open.map(\.id)))
        for session in open {
            guard let link = session.pullRequest, let repository = link.repository else { continue }
            do {
                let pullRequest = try await pullRequests.cli.pullRequest(link.number, in: repository)
                switch pullRequest.state {
                case .merged: pullRequestMerged(session.id, at: pullRequest.mergedAt ?? .now)
                case .closed: pullRequestClosed(session.id)
                case .open:
                    let flow = PullRequestFlow(cli: pullRequests.cli, worktrees: worktrees)
                    var isBehind = false
                    if let workspace = session.workspace { isBehind = (try? await flow.isBehind(workspace)) ?? false }
                    guard sessions.first(where: { $0.id == session.id })?.phase == .inRevisione else { continue }
                    pullRequests.record(PullRequestStatus(checks: pullRequest.checks, isBehind: isBehind),
                                        for: session.id)
                }
            } catch {
                Logger.sessions.error("Pull request not read: \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// The pull request of the Sessione `id` was merged on GitHub at `date`: Fusa, then as after Fondi once the
    /// merge cannot be undone, Archiviata with its worktree and its branch gone. Not while the agent works: the next
    /// reading does it.
    private func pullRequestMerged(_ id: UUID, at date: Date) {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .inRevisione, !session.isRunning
        else { return }
        Logger.sessions.notice("Pull request merged: \(session.pullRequest?.number ?? 0, privacy: .public)")
        pullRequests.forget(id)
        previews.close(id)
        update(id) { session in
            session.phase = .fusa
            session.mergedAt = date
        }
        onPhaseChange?(id, .fusa)
        update(id) { session in
            session.phase = .archiviata
            session.ports = nil
            session.isInterrupted = false
        }
        Task {
            // The shells leave the worktree before it goes.
            await terminals.closeAll(of: id)
            guard let workspace = session.workspace else { return }
            await worktrees.remove(workspace, of: session.project, deletingBranch: true)
        }
    }

    /// The pull request of the Sessione `id` was closed on GitHub without a merge: the Sessione is Aperta again,
    /// with a note, and Apri PR can open another one.
    private func pullRequestClosed(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .inRevisione,
              let link = session.pullRequest
        else { return }
        Logger.sessions.notice("Pull request closed: \(link.number, privacy: .public)")
        pullRequests.forget(id)
        update(id) { session in
            session.phase = .aperta
            session.pullRequest = nil
            session.summary = String(localized: "La PR #\(link.number) è stata chiusa su GitHub senza merge.")
        }
    }

    /// Aggiorna PR: commits what the Sessione `id` has not committed yet and pushes its branch to its pull request.
    /// Only In revisione, with the agent still; Bubo never pushes otherwise.
    ///
    /// - Throws: `PullRequestError`, `GitHubCLIError` or `WorktreeError`; the pull request stays as it was.
    func updatePullRequest(of id: UUID) async throws {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .inRevisione, !session.isRunning,
              session.pullRequest != nil, let workspace = session.workspace, merging.insert(id).inserted
        else { return }
        defer { merging.remove(id) }
        try await PullRequestFlow(cli: pullRequests.cli, worktrees: worktrees)
            .update(workspace, in: session.project, message: session.title)
        Logger.sessions.notice("Pull request updated")
        pullRequests.markUpToDate(id)
    }

    /// Aggiorna PR from a button or a menu: ``updatePullRequest(of:)``, with its failure kept for the Sessione's
    /// pull request to show.
    func requestPullRequestUpdate(of id: UUID) async {
        pullRequests.noteUpdate(of: id, isRunning: true)
        do {
            try await updatePullRequest(of: id)
            pullRequests.noteUpdate(of: id, isRunning: false)
        } catch {
            Logger.sessions.error("Pull request not updated: \(String(describing: error), privacy: .private)")
            pullRequests.noteUpdate(of: id, isRunning: false,
                                    failure: (error.localizedDescription, (error as? GitHubCLIError)?.remedy))
        }
    }

    /// Correggi: sends the failed checks of the pull request of the Sessione `id` to the agent, as a new turn in its
    /// copy, with the failed log of each GitHub Actions job. Nothing without a failed check, or while it works.
    func fixChecks(of id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .inRevisione, !session.isRunning,
              session.workspace != nil, let link = session.pullRequest, let repository = link.repository,
              let failed = pullRequests.statuses[id]?.failedChecks, !failed.isEmpty, merging.insert(id).inserted
        else { return }
        var failures: [(check: PullRequestCheck, log: String?)] = []
        for check in failed {
            let log: String? = if let job = check.jobID {
                try? await pullRequests.cli.failedLog(ofJob: job, in: repository)
            } else {
                nil
            }
            failures.append((check, log))
        }
        merging.remove(id)
        guard let current = sessions.first(where: { $0.id == id }), current.phase == .inRevisione,
              !current.isRunning
        else { return }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.failure = nil
            session.isInterrupted = false
        }
        let prompt = PullRequestFlow.fixPrompt(forPullRequest: link.number, failures: failures)
        turnTasks[id] = Task { await run(id, prompt: prompt, branch: session.branchToPrepare) }
    }

    /// Brings the branch of the Progetto's checkout into the Sessione `id`, in its worktree, and asks the agent to
    /// resolve the conflicts there, as a new turn of the Sessione. Once they are resolved, the revisione compares
    /// with that branch: the resolution is new blocchi to review before Fondi. When the turn fails or leaves
    /// conflict markers, the worktree goes back as it was. The Progetto's checkout is never touched.
    ///
    /// - Throws: `MergeError.detachedHead` when the checkout is not on a branch; `WorktreeError` when git fails.
    ///   Nothing changes then.
    func resolveConflicts(_ id: UUID) async throws {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta, !session.isRunning,
              session.resolution == nil, let workspace = session.workspace, workspace.branch != nil,
              merging.insert(id).inserted
        else { return }
        defer { merging.remove(id) }
        let resolution = try await worktrees.bringIn(session.project, into: workspace)
        update(id) { $0.resolution = resolution }
        Logger.sessions.notice("Conflicts brought into the Sessione: \(resolution.conflicts.count)")
        guard !resolution.conflicts.isEmpty else {
            await finishResolving(id, succeeded: true)
            return
        }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.failure = nil
            session.isInterrupted = false
        }
        let prompt = String(localized: "Ho portato in questo branch le ultime modifiche di \(resolution.branch) e git ha lasciato conflitti in \(resolution.conflicts.formatted()). Risolvili nei file tenendo sia il tuo lavoro sia quello di \(resolution.branch), e togli tutti i marcatori <<<<<<<, ======= e >>>>>>>. Non fare commit e non annullare il merge: lo concludo io.")
        Task {
            let succeeded = await run(id, prompt: prompt, branch: session.branchToPrepare)
            await finishResolving(id, succeeded: succeeded)
        }
    }

    /// Ends the conflict resolution of the Sessione `id`: with a commit in its worktree and the revisione based on
    /// the branch brought in when the agent `succeeded` and left no markers; otherwise with the worktree as it was,
    /// and the Sessione in Errore.
    private func finishResolving(_ id: UUID, succeeded: Bool) async {
        guard let session = sessions.first(where: { $0.id == id }), let resolution = session.resolution,
              let workspace = session.workspace
        else { return }
        var failure = MergeError.unresolved(resolution.conflicts).localizedDescription
        if succeeded {
            do {
                try await worktrees.conclude(resolution, in: workspace)
                update(id) { session in
                    session.resolution = nil
                    session.workspace?.base = resolution.incoming
                }
                return
            } catch let error as MergeError {
                failure = error.localizedDescription
            } catch {
                Logger.sessions.error("Resolution not concluded: \(String(describing: error), privacy: .private)")
            }
        }
        do {
            try await worktrees.restore(resolution, in: workspace)
        } catch {
            Logger.sessions.error("Worktree not restored: \(String(describing: error), privacy: .private)")
            let reason = if case let WorktreeError.git(message) = error {
                message.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                error.localizedDescription
            }
            failure = String(localized: "Non riesco a rimettere la copia della Sessione com'era dopo i conflitti: \(reason)")
        }
        update(id) { session in
            session.resolution = nil
            session.enter(.errore)
            session.failure = failure
            session.unstartedPrompt = nil
            session.isInterrupted = false
        }
    }

    /// Annulla merge: puts the Progetto's checkout back as it was before Fondi, and the Sessione back to Aperta.
    ///
    /// - Throws: `MergeError.moved` or `WorktreeError` when the checkout changed since; the merge then stays,
    ///   and the Sessione is Archiviata.
    func undoMerge(_ id: UUID) async throws {
        guard let pending = merges.removeValue(forKey: id) else { return }
        pending.finishing.cancel()
        undoDeadlines[id] = nil
        do {
            try await worktrees.undo(pending.merge)
        } catch {
            Logger.sessions.error("Merge not undone: \(String(describing: error), privacy: .private)")
            finishMerge(id)
            throw error
        }
        update(id) { session in
            session.phase = .aperta
            session.mergedAt = nil
        }
    }

    /// Archives the Fusa Sessione `id`: its worktree and its branch go in the background, its ports are free again.
    private func finishMerge(_ id: UUID) {
        merges.removeValue(forKey: id)?.finishing.cancel()
        undoDeadlines[id] = nil
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .fusa else { return }
        update(id) { session in
            session.phase = .archiviata
            session.ports = nil
            session.isInterrupted = false
        }
        guard let workspace = session.workspace else { return }
        Task { await worktrees.remove(workspace, of: session.project, deletingBranch: true) }
    }

    /// Archives a Sessione: its worktree goes in the background, its branch stays, its ports are free again.
    func archive(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.isLive, !session.isRunning
        else { return }
        update(id) { session in
            session.phase = .archiviata
            session.ports = nil
            session.isInterrupted = false
        }
        onPhaseChange?(id, .archiviata)
        previews.close(id)
        Task {
            // The shells leave the worktree before it goes.
            await terminals.closeAll(of: id)
            guard let workspace = session.workspace else { return }
            await worktrees.remove(workspace, of: session.project, deletingBranch: false)
        }
    }

    /// Archives the Sessione of an Esecuzione Senza modifiche, with nothing to look at: no Riassunto, and its worktree
    /// and its branch gone by the time it returns.
    func archiveUnchanged(_ id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }), session.isLive, !session.isRunning else { return }
        update(id) { session in
            session.phase = .archiviata
            session.ports = nil
            session.isInterrupted = false
        }
        previews.close(id)
        await terminals.closeAll(of: id)
        guard let workspace = session.workspace else { return }
        await worktrees.remove(workspace, of: session.project, deletingBranch: true)
    }

    /// Records the Riassunto di Sessione of `id`: the note Bubo wrote, when it wrote one, and whether it still waits.
    func recordSummary(_ note: SummaryNote?, isPending: Bool, in id: UUID) {
        update(id) { session in
            if let note { session.summaryNote = note }
            session.isSummaryPending = isPending
        }
    }

    /// What deleting the Sessione `id` would lose, as file paths and commit subjects.
    func lostChanges(_ id: UUID) async -> [String] {
        guard let session = sessions.first(where: { $0.id == id }), let workspace = session.workspace else { return [] }
        return await worktrees.lostChanges(in: workspace, of: session.project)
    }

    /// Deletes a Sessione with its worktree, its branch and the copies of its conversations, in the background.
    func delete(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), !session.isRunning else { return }
        merges.removeValue(forKey: id)?.finishing.cancel()
        undoDeadlines[id] = nil
        turnTasks[id] = nil
        sessions.removeAll { $0.id == id }
        permissions.forget(id)
        questions[id] = nil
        sandboxBlocks[id] = nil
        previews.close(id)
        Task { await terminals.closeAll(of: id) }
        save()
        followActivity()
        if !session.conversations.isEmpty {
            Task { [indexer] in await indexer?.forget(session.conversations) }
            Task {
                do {
                    try await bridge().forget(session.conversations)
                } catch {
                    Logger.sessions.error("Conversations not forgotten: \(String(describing: error), privacy: .private)")
                }
            }
        }
        guard let workspace = session.workspace else { return }
        Task { await worktrees.remove(workspace, of: session.project, deletingBranch: true) }
    }

    /// Why an open Sessione cannot work any more: its Progetto or its worktree is gone.
    private static func missingFolder(of session: Session) -> String? {
        guard session.isLive else { return nil }
        if !FileManager.default.fileExists(atPath: session.project.path) {
            return String(localized: "Il Progetto non è più in \(session.project.path). Riporta lì la cartella o cancella la Sessione.")
        }
        if let workspace = session.workspace, workspace.branch != nil,
           !FileManager.default.fileExists(atPath: workspace.folder.path) {
            return String(localized: "La copia isolata della Sessione non è più in \(workspace.folder.path). Cancella la Sessione per toglierla dall'elenco.")
        }
        return nil
    }

    /// Whether `prompt` may call a skill with `/name`: at its start, or at the start of the request after the turns of a
    /// Domanda; only then is the catalog read.
    nonisolated static func mayCallSkill(_ prompt: String) -> Bool {
        prompt.hasPrefix("/") || prompt.contains(QuestionTurn.asking("/"))
    }

    /// `prompt` with the skill it calls by `/name` written into it, and that skill; `prompt` whole and `nil` when it
    /// calls none of `skills`, or when Claude runs the skill on its own: `/name` at the start of a Claude turn.
    ///
    /// The `/name` may also start the request after the quoted turns of a Domanda (``SessionDraft/firstPrompt(_:)``):
    /// then the instructions go before the turns, and the request loses its `/name`.
    ///
    /// - Parameter forClaude: Whether Claude answers, and may read the skill's folder.
    nonisolated static func expandingSkill(in prompt: String, among skills: [Skill],
                                           forClaude: Bool) -> (prompt: String, skill: Skill?) {
        if forClaude, prompt.hasPrefix("/") { return (prompt, nil) }
        if let invocation = SkillInvocation(parsing: prompt, among: skills) {
            return (invocation.expanded(showingFolder: forClaude), invocation.skill)
        }
        guard let asking = prompt.range(of: QuestionTurn.asking(""), options: .backwards),
              let invocation = SkillInvocation(parsing: String(prompt[asking.upperBound...]), among: skills)
        else { return (prompt, nil) }
        // The `/name` and the spaces after it leave the request.
        let call = prompt[asking.upperBound...].dropFirst(invocation.skill.name.count + 1)
        let rest = prompt[..<asking.upperBound] + call.drop { $0 == " " }
        let expanded = SkillInvocation(skill: invocation.skill, request: String(rest))
        return (expanded.expanded(showingFolder: forClaude), invocation.skill)
    }

    /// Prepares the Sessione's copy on `branch` if it has none yet, then asks `claude` `prompt` there.
    ///
    /// Each turn is a new Conversazione that resumes ``Session/continuedConversation`` as a fork, and takes its place
    /// once `claude` ran it: when it ends, or fails after answering. An interrupted turn leaves it as it was, so that
    /// Riavvia and Riprendi start from the same point.
    ///
    /// - Parameters:
    ///   - reopening: The copy of the Archiviata Sessione that Riprendi prepares again, in place of a new one.
    ///   - unattended: Makes it the turn of an Esecuzione, with nobody in front of it.
    /// - Returns: Whether the turn ended without errors.
    @discardableResult
    private func run(_ id: UUID, prompt: String, branch: String, reopening: Workspace? = nil,
                     unattended: UnattendedTurn? = nil, ignoringBudget: Bool = false) async -> Bool {
        guard let session = sessions.first(where: { $0.id == id }) else { return false }
        // The Allegati dropped on the Sessione go with this turn, and only with it.
        let attachments = session.attachments
        let isCopilot = session.engine == .copilot && unattended == nil
        // A `/name` Claude runs on its own stays as it is; otherwise Bubo writes the skill into the prompt (#689).
        var skill: Skill?
        var asked = prompt
        if Self.mayCallSkill(prompt) {
            (asked, skill) = Self.expandingSkill(in: prompt, among: await SkillCatalog.skills(in: session.project),
                                                 forClaude: !isCopilot)
        }
        let prompt = QuestionModel.prompt(asked, attachments: attachments)
        // Kept from the start, also before the copy is ready: Riprendi asks this turn again if Bubo quits.
        update(id) { session in
            session.turnPrompt = prompt
            session.attachments = []
            session.budgetStop = nil
        }
        let environment = session.portEnvironment
        // A Copilot turn never calls `claude`, nor has its Sandbox and plugins (ADR 0012); it is always Spesa, in
        // Copilot's Budget (#542).
        let provider = isCopilot ? Budgets.copilot : Budgets.claude
        var conversation: String?
        var hasAnswered = false
        do {
            // Before the copy and the prompt: a `claude` too old starts nothing.
            if !isCopilot, let version = await outdatedClaude() { throw AgentBridgeError.claudeOutdated(version: version) }
            let workspace: Workspace
            if let prepared = session.workspace {
                workspace = prepared
            } else {
                let preparing = Signposts.signposter.beginInterval("Sessione pronta",
                                                                   id: Signposts.signposter.makeSignpostID())
                workspace = if let reopening {
                    try await worktrees.reopen(reopening, of: session.project)
                } else {
                    try await worktrees.prepare(session.project, branch: branch)
                }
                Signposts.signposter.endInterval("Sessione pronta", preparing)
                update(id) { $0.workspace = workspace }
                if let failure = await worktrees.runSetup(in: workspace, environment: environment) {
                    update(id) { $0.setupFailure = failure }
                }
            }
            let agent = try await bridge()
            // With the API key, or on Copilot, the turn gets the shared residue as its cap; spent, nothing is sent
            // (spec 18).
            let isPaidPerUse = isCopilot || agent.usesAPIKey
            let maxBudget = isPaidPerUse && !ignoringBudget ? try budgetCap(of: provider, in: session.project) : nil
            let classifier = RiskClassifier(workingDirectory: workspace.folder)
            let isSandboxed = !isCopilot && ReleaseArea.sandbox.isAvailable() && sandbox.isEnabled(in: session.project)
            // The Anteprima's tools exist only while the Sessione has a server (spec 15).
            let answerID = UUID().uuidString
            let hasServer = servers.servers[id]?.isEmpty == false
            // Read now: the copy may have just been prepared, and the switch may have changed since the turn was asked.
            let permissionMode = sessions.first { $0.id == id }?.permissionMode ?? .manual
            turns[id] = agent
            turnPrompts[id] = prompt
            watchFootprints()
            sandboxedTurns[id] = isSandboxed
            sandboxBlocks[id] = nil
            if unattended != nil {
                update(id) { session in
                    session.denials = []
                    session.effectiveMode = nil
                }
            }
            previewOffers[id] = (answerID, hasServer)
            if !isCopilot { pluginReloader.turnDidStart(in: id, folder: workspace.folder) }
            if maxBudget != nil { budgetedTurns[id] = (provider, session.project) }
            defer {
                pluginReloader.turnDidEnd(in: id)
                budgetedTurns[id] = nil
                turns[id] = nil
                turnPrompts[id] = nil
                footprints.forget(id)
                sandboxedTurns[id] = nil
                previewOffers[id] = nil
                permissions.clear(id)
                questions[id] = nil
            }
            // Each turn is a conversation of its own, which Bubo keeps (ADR 0006). A Sessione on Copilot keeps one, the
            // session of `copilot`, which each turn resumes (#553): never a conversation `claude` could resume.
            let copilotConversation = isCopilot ? sessions.first { $0.id == id }?.copilotConversation : nil
            let kept = copilotConversation ?? UUID().uuidString.lowercased()
            if !isCopilot { conversation = kept }
            update(id) { session in
                if copilotConversation == nil { session.conversations.append(kept) }
                if isCopilot { session.copilotConversation = kept }
            }
            defer { keepEstimate(of: kept, in: session.project) }
            // Also after an error: what was said enters the Indice.
            defer { Task { [indexer, project = session.project] in await indexer?.add(kept, in: project) } }
            // Read now: Riavvia may have just interrupted the turn before.
            let current = sessions.first { $0.id == id }
            let resumed = current?.continuedConversation
            // Continua da qui cuts only the conversation it forked: the turns after resume theirs whole.
            let cut = resumed != nil && resumed == current?.forkedFrom ? current?.forkedUpTo : nil
            // An Esecuzione keeps the model of its Automazione; the others take the one chosen in the Sessione.
            let chosen = unattended == nil ? current?.model : nil
            let onProgress: (AgentProgress) -> Void = { [weak self] progress in
                // A tool at work answers too: the onboarding must not call `claude` silent (spec 26).
                self?.onFirstToken()
                switch progress {
                case .ranCommand: self?.servers.notice()
                case let .variante(nome): self?.orb?.showWork(nome)
                case let .sandboxBlock(block): self?.record(block, in: id)
                case let .denial(reported): self?.record(Denial(reported, classifier: classifier), in: id)
                case .read: self?.onFileActivity?(id, progress)
                case .edit:
                    self?.update(id) { $0.apply(progress) }
                    self?.onFileActivity?(id, progress)
                default: self?.update(id) { $0.apply(progress) }
                }
            }
            let onPermission: (PermissionEvent) -> Void = { [weak self] event in
                // Waiting for the user's consent is not silence.
                self?.onFirstToken()
                self?.receive(event, in: id, from: agent, classifier: classifier)
            }
            let copilot = isCopilot ? try await copilotURL() : nil
            let answer = if let copilot {
                agent.askCopilot(prompt, in: workspace.folder, copilot: copilot, consents: copilotConsents(),
                                 model: current?.copilotModel?.model, effort: current?.copilotModel?.effort,
                                 keeping: kept, resuming: copilotConversation != nil, id: answerID, progress: onProgress,
                                 permissions: onPermission) { [weak self, ledger, copilotPrices] usage in
                    ledger.record(copilotPrices.spesa(of: usage), turn: kept, session: id, project: session.project,
                                  provider: Budgets.copilot)
                    self?.stopTurnsPastBudget(besides: id)
                }
            } else {
                agent.ask(prompt, in: workspace.folder, model: unattended?.model ?? chosen?.family.alias,
                          effort: chosen?.effort, environment: environment,
                          forkingFrom: resumed, upTo: cut, keeping: kept,
                          isSandboxed: isSandboxed, sandboxAllowances: sandbox.allowances(in: session.project),
                          permissionMode: permissionMode, id: answerID,
                          offersPreview: hasServer, remembers: unattended == nil, unattended: unattended,
                          readableDirectories: QuestionModel.readableDirectories(for: attachments, skill: skill),
                          maxBudget: maxBudget, progress: onProgress, permissions: onPermission) { [weak self, ledger] usage in
                ledger.record(usage, turn: kept, session: id, project: session.project)
                if usage.isComplete { self?.estimates[kept] = nil }
                self?.stopTurnsPastBudget(besides: id)
            } estimate: { [weak self] usage in
                self?.estimate(usage, turn: kept, session: id, project: session.project)
            } preview: { [weak self] action in
                await self?.drivePreview(action, in: id) ?? .failure("Bubo non pilota più questa Sessione.")
            } isDangerous: { request in
                classifier.risk(of: request).isDangerous
            }
            }
            for try await _ in answer where !hasAnswered {
                hasAnswered = true
                onFirstToken()
            }
            if budgetStops.remove(id) != nil { throw AgentBridgeError.budgetExhausted }
            update(id) { session in
                session.enter(.ferma)
                // A Copilot turn leaves no conversation of `claude` to resume: the next resumes `copilotConversation`.
                if !Task.isCancelled, !isCopilot { session.continuedConversation = kept }
            }
            return true
        } catch {
            if hasAnswered, !Task.isCancelled, let conversation {
                update(id) { $0.continuedConversation = conversation }
            }
            Logger.sessions.error("Sessione failed: \(String(describing: error), privacy: .private)")
            onTurnFailure(id, error)
            update(id) { session in
                session.enter(.errore)
                switch error {
                case AgentBridgeError.sandboxUnavailable, AgentBridgeError.claudeOutdated,
                     CopilotFailure.consentMissing:
                    session.unstartedPrompt = prompt
                default:
                    session.unstartedPrompt = nil
                }
                session.failure = switch error {
                case let WorktreeError.git(message): message.trimmingCharacters(in: .whitespacesAndNewlines)
                case let AgentBridgeError.failed(message): message
                case let AgentBridgeError.turnFailed(failure): failure.message
                // ponytail: the three choices at the limit are in the Domanda; the Sessione says only why it stopped.
                case AgentBridgeError.limitReached: String(localized: "Hai raggiunto il limite dell'abbonamento.")
                case AgentBridgeError.signInRequired: String(localized: "L'accesso a Claude è scaduto.")
                // The Sessione shows the Budget spent and the choices instead.
                case AgentBridgeError.budgetExhausted: nil
                case let AgentBridgeError.sandboxUnavailable(reason):
                    String(localized: "Sandbox non disponibile: \(reason). La Sessione non è partita.")
                case let AgentBridgeError.claudeOutdated(version?):
                    String(localized: "Claude Code \(version) è troppo vecchio per Bubo. Aggiornalo e la Sessione parte da sola.")
                case AgentBridgeError.claudeOutdated:
                    String(localized: "Claude Code è troppo vecchio per Bubo. Aggiornalo e la Sessione parte da sola.")
                case QuestionFailure.claudeMissing: String(localized: "Claude Code non trovato: installa la CLI claude.")
                case CopilotFailure.missing: String(localized: "GitHub Copilot non trovato: installa la CLI copilot.")
                case CopilotFailure.consentMissing:
                    String(localized: "Senza il tuo consenso Copilot non può ricevere i file del Progetto. Puoi darlo in Impostazioni › Modelli.")
                default: String(localized: "Il collegamento con Claude si è interrotto.")
                }
            }
            if case let AgentBridgeError.claudeOutdated(version) = error {
                awaitingClaudeUpdate.insert(id)
                onClaudeOutdated(version)
            }
            if case AgentBridgeError.budgetExhausted = error {
                budgetStops.remove(id)
                let scope = spentBudget(of: provider, in: session.project)
                // Ferma, not in Errore: it waits for the user's choice, and its turn is kept for it.
                update(id) { session in
                    session.enter(.ferma)
                    session.failure = nil
                    session.unstartedPrompt = prompt
                    session.budgetStop = scope
                }
            }
            return false
        }
    }

    /// The user's `copilot`.
    ///
    /// - Throws: `CopilotFailure.missing` when there is none.
    private func copilotURL() async throws -> URL {
        guard let copilot = await locateCopilot() else { throw CopilotFailure.missing }
        return copilot
    }

    /// The cap of a turn paid per use to `provider` on `project`: what the tightest Budget has left; `nil` without a
    /// Budget.
    ///
    /// - Throws: `AgentBridgeError.budgetExhausted` when a Budget the turn counts in is spent.
    private func budgetCap(of provider: String, in project: URL) throws -> Decimal? {
        switch BudgetGuard(budgets: budgets.budgets, entries: budgetEntries)
            .allowance(provider: provider, project: project) {
        case .unlimited: nil
        case let .upTo(residue): residue
        case .exhausted: throw AgentBridgeError.budgetExhausted
        }
    }

    /// The spent Budget a turn of `provider` on `project` counts in; the provider's when the ledger does not show one
    /// spent yet.
    private func spentBudget(of provider: String, in project: URL) -> BudgetGuard.Scope {
        let guarded = BudgetGuard(budgets: budgets.budgets, entries: budgetEntries)
        if case let .exhausted(scope) = guarded.allowance(provider: provider, project: project) { return scope }
        return guarded.tightest(provider: provider, project: project)?.scope ?? .provider(provider)
    }

    /// The ledger's turns, with the estimate of each turn in progress in place of what it reported so far.
    private var budgetEntries: [CostLedger.Entry] {
        ledger.entries.filter { estimates[$0.id] == nil } + estimates.values
    }

    /// Counts `usage`, the tokens of the turn `turn` so far, in the Budgets at Bubo's prices, and stops every turn past
    /// them, this one too: each Sessione goes over by at most the answer it was writing (#492).
    private func estimate(_ usage: TurnUsage, turn: String, session: UUID, project: URL) {
        guard let prices else { return }
        estimates[turn] = CostLedger.Entry(id: turn, session: session, project: project, provider: Budgets.claude,
                                           date: .now, usage: prices.estimate(usage))
        stopTurnsPastBudget(besides: nil)
    }

    /// Records the estimate of the turn `turn`, just ended, when no `result` gave its figure: interrupted, stopped by a
    /// Budget, or crashed. Marked incomplete.
    private func keepEstimate(of turn: String, in project: URL) {
        guard let estimate = estimates.removeValue(forKey: turn),
              ledger.entries.last(where: { $0.id == turn })?.usage.isComplete != true else { return }
        ledger.record(estimate.usage, turn: turn, session: estimate.session, project: project)
    }

    /// Stops at once every turn in progress capped by a Budget now spent, besides `reporting`, whose figure just
    /// arrived at its end: each Sessione goes over by at most the answer it was writing (spec 18).
    private func stopTurnsPastBudget(besides reporting: UUID?) {
        guard budgetedTurns.keys.contains(where: { $0 != reporting }) else { return }
        let guarded = BudgetGuard(budgets: budgets.budgets, entries: budgetEntries)
        for (id, turn) in budgetedTurns where id != reporting {
            guard case .exhausted = guarded.allowance(provider: turn.provider, project: turn.project) else { continue }
            budgetedTurns[id] = nil
            budgetStops.insert(id)
            turnTasks[id]?.cancel()
        }
    }

    /// Reads the footprint of each turn's `claude` every 30 s, until no turn is in progress.
    private func watchFootprints() {
        guard footprintWatch == nil else { return }
        footprintWatch = Task { [weak self] in
            while self?.readFootprints() == true {
                try? await Task.sleep(for: ProcessFootprintMonitor.interval)
            }
        }
    }

    /// Records the footprint of each turn's `claude`, found among the children of its bridge by its conversation.
    ///
    /// - Returns: `false`, ending the watch, once no turn is in progress.
    private func readFootprints() -> Bool {
        guard !turns.isEmpty else {
            footprintWatch = nil
            return false
        }
        var claudes: [pid_t: [String: pid_t]] = [:]
        var readings: [UUID: UInt64] = [:]
        for (id, agent) in turns {
            guard let bridge = agent.pid, let conversation = sessions.first(where: { $0.id == id })?.conversations.last
            else { continue }
            let processes = claudes[bridge] ?? ProcessInspector.claudeProcesses(of: bridge)
            claudes[bridge] = processes
            if let pid = processes[conversation], let footprint = ProcessInspector.footprint(of: pid) {
                readings[id] = footprint
            }
        }
        footprints.record(readings)
        return true
    }

    /// Turns the Modalità autonoma of the Sessione `id` on or off, from its next turn; nothing where it is not possible.
    func setAutonomous(_ isAutonomous: Bool, in id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.allowsAutonomy || !isAutonomous else { return }
        update(id) { $0.isAutonomous = isAutonomous }
    }

    /// Makes the turns of the Sessione `id` run on `choice`, from its next one: the current turn keeps its model.
    func setChoice(_ choice: EngineChoice, in id: UUID) {
        update(id) { $0.choice = choice }
    }

    /// Reads the models of the user's Copilot plan into ``copilotModels``, unless already read; `again` reads them
    /// anyway, after a login. Without `copilot`, or signed out, the list is empty.
    func loadCopilotModels(again: Bool = false) async {
        guard again || copilotModels?.isEmpty != false else { return }
        guard let copilot = await locateCopilot() else {
            copilotModels = []
            return
        }
        do {
            copilotModels = if let readCopilotModels {
                try await readCopilotModels(copilot)
            } else {
                try await bridge().copilotModels(of: copilot)
            }
        } catch {
            Logger.sessions.error("Copilot models unreadable: \(String(describing: error), privacy: .public)")
            copilotModels = []
        }
    }

    /// Whether a Sessione of the Progetto at `project` is in a turn: Bubo then never writes in its memory.
    func isInTurn(_ project: URL) -> Bool {
        sessions.contains { $0.project == project && $0.isRunning }
    }

    /// Annulla of the line Ricordato or Salvato `line` of the Sessione `id`: puts the file back as it was before the
    /// write.
    ///
    /// - Throws: ``ProjectMemoryError/inTurn`` while a Sessione of the Progetto is in a turn,
    ///   ``ProjectMemoryError/changedOnDisk`` when the file changed after the write, or another error of
    ///   ``MemoryWrite/undo(in:)``. The line stays as it was then.
    func undo(_ line: MemoryLine.ID, in id: UUID) throws {
        guard let session = sessions.first(where: { $0.id == id }),
              let memoryLine = session.memoryLines.first(where: { $0.id == line }), memoryLine.canUndo
        else { return }
        switch memoryLine.event {
        case let .remembered(write):
            guard !isInTurn(session.project) else { throw ProjectMemoryError.inTurn }
            try write.undo(in: ProjectMemory.directory(ofProject: session.project))
        case let .saved(change):
            try undoSaved?(change)
        case .recalled, .searched:
            return
        }
        update(id) { session in
            guard let index = session.memoryLines.firstIndex(where: { $0.id == line }) else { return }
            session.memoryLines[index].isUndone = true
        }
    }

    /// Answers the Richiesta di permesso `request` of the Sessione `id`; nothing if `claude` no longer waits for it.
    func answer(_ request: PermissionRequest.ID, in id: UUID, with answer: PermissionAnswer) {
        let isLasting = (answer == .allowForSession || answer == .allowInProject)
            && permissions.pending(request, in: id)?.allowsSessionRule == true
        guard let allows = permissions.answer(request, in: id, with: answer) else { return }
        turns[id]?.answerPermission(request, allows: allows, isLasting: isLasting)
        followActivity()
    }

    /// Answers the agent's questions `question` of the Sessione `id` with `replies`, one per question in order; `nil`
    /// when the user does not answer. Nothing if `claude` no longer waits for them.
    func answer(_ question: AgentQuestion.ID, in id: UUID, with replies: [AgentQuestion.Reply]?) {
        guard let index = questions[id]?.firstIndex(where: { $0.id == question }) else { return }
        questions[id]?.remove(at: index)
        if questions[id]?.isEmpty == true { questions[id] = nil }
        turns[id]?.answerQuestion(question, with: replies)
        followActivity()
    }

    /// Answers from its notification the Richiesta di permesso `request` of the Sessione `id`: nothing if `claude` no
    /// longer waits for it, and no approval unless the notification could offer Solo ora.
    func answerFromNotification(_ request: PermissionRequest.ID, in id: UUID, allows: Bool) {
        guard let allows = permissions.answerFromNotification(request, in: id, allows: allows) else {
            Logger.sessions.notice("Notification answer ignored: the Richiesta no longer waits or needs the HUD")
            return
        }
        turns[id]?.answerPermission(request, allows: allows)
        followActivity()
    }

    /// Answers Sempre in questo Progetto: saves the rule of the Richiesta `request` in the Progetto of the Sessione `id`,
    /// then allows the call. Nothing if `claude` no longer waits for it or no rule is offered.
    ///
    /// - Throws: `RuleStoreError.untrusted` until the Progetto is trusted, since `claude` would not read the rule;
    ///   `RuleStoreError` or a file error when it cannot be saved. The Richiesta keeps waiting then.
    func allowInProject(_ request: PermissionRequest.ID, in id: UUID) throws {
        guard let session = sessions.first(where: { $0.id == id }),
              let rule = permissions.pending(request, in: id)?.projectRule
        else { return }
        guard worktrees.trustGate.isTrusted(session.project) else { throw RuleStoreError.untrusted }
        try RuleStore(project: session.project).add(rule.text)
        answer(request, in: id, with: .allowInProject)
    }

    /// Answers Sempre in questo Progetto to a Richiesta "Rete: host": adds its host to the Sandbox of the Progetto of the
    /// Sessione `id`, in Bubo's store and never in the settings, then allows the call for the rest of the Sessione.
    /// Nothing if `claude` no longer waits for it or it is not such a Richiesta.
    func allowDomainInProject(_ request: PermissionRequest.ID, in id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }),
              let domain = permissions.pending(request, in: id)?.projectDomain
        else { return }
        sandbox.allow(domain, in: session.project)
        answer(request, in: id, with: .allowInProject)
    }

    /// Keeps `denial` in the report of the Sessione `id`, once: a later report of the same call replaces it.
    private func record(_ denial: Denial, in id: UUID) {
        update(id) { session in
            session.denials.removeAll { $0.id == denial.id }
            session.denials.append(denial)
        }
    }

    /// Keeps `block` among the latest of the Sessione `id`, once.
    private func record(_ block: SandboxBlock, in id: UUID) {
        var blocks = sandboxBlocks[id] ?? []
        blocks.removeAll { $0 == block }
        blocks.append(block)
        sandboxBlocks[id] = Array(blocks.suffix(Self.sandboxBlockLimit))
    }

    /// Queues a Richiesta di permesso of the Sessione `id`, or answers it at once: no to a critical path,
    /// yes to what the user already allowed "Per questa Sessione". Queues the agent's questions too.
    private func receive(_ event: PermissionEvent, in id: UUID, from bridge: AgentBridge, classifier: RiskClassifier) {
        switch event {
        case let .asked(request):
            switch permissions.receive(request, in: id, risk: classifier.risk(of: request)) {
            case .denied:
                Logger.sessions.notice("Critical path refused: \(request.tool, privacy: .public)")
                bridge.answerPermission(request.id, allows: false)
            case .allowed:
                bridge.answerPermission(request.id, allows: true, isLasting: true)
            case .queued:
                break
            }
        case let .question(question):
            questions[id, default: []].append(question)
        case let .withdrawn(request):
            permissions.withdraw(request, in: id)
            questions[id]?.removeAll { $0.id == request }
            if questions[id]?.isEmpty == true { questions[id] = nil }
        }
        followActivity()
    }

    /// Gives the Anteprima's tools to the turns in progress whose Sessione now has a server, and takes them away when
    /// its last server goes.
    private func offerPreviews(to servers: [UUID: [ListeningSocket]]) {
        for (id, offer) in previewOffers {
            let hasServer = servers[id]?.isEmpty == false
            guard hasServer != offer.isOffered else { continue }
            previewOffers[id]?.isOffered = hasServer
            turns[id]?.offerPreview(hasServer, to: offer.answer)
        }
    }

    private func update(_ id: UUID, _ change: (inout Session) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
        save()
        followActivity()
    }

    /// The Sessione the Orb's Stato follows alone: the one the Galassia in focus filters on; `nil` for all of them.
    var orbFocus: UUID? {
        didSet { if orbFocus != oldValue { followActivity() } }
    }

    /// Gives the Orb the Stato of the Sessioni's Attività, and tells the user which ones wait.
    private func followActivity() {
        let state = OrbState(following: sessions, focus: orbFocus)
        if orb?.state != state { orb?.state = state }
        alerts?.follow(sessions, requests: permissions)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sessions).write(to: file, options: .atomic)
        } catch {
            Logger.sessions.error("Sessioni not saved: \(error)")
        }
    }
}

/// Why a Sessione cannot start.
nonisolated enum SessionError: LocalizedError, Equatable {
    /// Another open Sessione, with this title, already works on the Progetto's checkout.
    case checkoutTaken(by: String)

    var errorDescription: String? {
        switch self {
        case let .checkoutTaken(title):
            String(localized: "«\(title)» lavora già sul checkout di questo Progetto. Archiviala, o lavora in una copia isolata.")
        }
    }
}

extension OrbState {
    /// The Stato for these Sessioni: Ascolto while an open one is in Attende te, since it waits for the user;
    /// Lavora while one works; Riposo otherwise.
    /// With a `focus` among the open Sessioni, such as the one the Galassia in focus filters on, the Stato follows
    /// that one alone.
    // ponytail: the HUD has no Sessione in front of the user yet; then the Stato follows that one alone.
    init(following sessions: [Session], focus: UUID? = nil) {
        var open = sessions.filter { $0.isLive }
        if let focused = open.first(where: { $0.id == focus }) { open = [focused] }
        if open.contains(where: { $0.activity == .attende }) {
            self = .listening
        } else if open.contains(where: { $0.activity == .lavora }) {
            self = .working
        } else {
            self = .idle
        }
    }
}
