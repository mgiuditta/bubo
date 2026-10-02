import Foundation
import os

/// The Sessioni of every Progetto, kept in a JSON file across launches.
@Observable
final class SessionStore {
    /// The Sessioni, oldest first.
    private(set) var sessions: [Session] = []
    /// The Richieste di permesso waiting in the Sessioni, and the permissions given "Per questa Sessione".
    private(set) var permissions = RequestCenter()
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
    init(file: URL, worktrees: WorktreeManager, orb: OrbControls? = nil, alerts: WaitingAlerts? = nil,
         ledger: CostLedger = CostLedger(), drafts: DraftStore = DraftStore(), sandbox: SandboxStore = SandboxStore(),
         bridge: @escaping () async throws -> AgentBridge) {
        self.file = file
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
    /// Whether each Progetto runs its Sessioni's commands in the Sandbox; a change counts from the next turn.
    @ObservationIgnored let sandbox: SandboxStore
    /// The terminals of the Sessioni, closed at Archivia, Fondi and Cancella.
    @ObservationIgnored let terminals = TerminalStore()
    /// The servers the Sessioni started, from their terminals or their agent.
    @ObservationIgnored let servers = PortWatcher()
    /// The Anteprime of the Sessioni's servers, closed with their server and at Archivia, Fondi and Cancella.
    @ObservationIgnored let previews = PreviewStore()
    /// The visore, for the files ⌘-clicked in the terminals.
    @ObservationIgnored let viewer = CodeViewerStore()
    /// Called at the first token of each turn's answer; the onboarding ends at the first one (spec 26).
    @ObservationIgnored var onFirstToken: () -> Void = {}
    /// What brings each turn's conversation into the Indice when it ends; `nil` without an Indice.
    @ObservationIgnored var indexer: ConversationIndexer?
    /// Called when a turn of a Sessione fails, with why; the onboarding offers a remedy for the first one (spec 26).
    @ObservationIgnored var onTurnFailure: (_ session: UUID, _ error: any Error) -> Void = { _, _ in }
    /// Which Sessioni have a heavy `claude`, read every 30 s while a turn is in progress (spec 25).
    @ObservationIgnored let footprints = ProcessFootprintMonitor()
    /// The turns in progress, which `restart` and `restartTurn` interrupt; not those resolving conflicts.
    @ObservationIgnored private var turnTasks: [UUID: Task<Void, Never>] = [:]
    /// The version of `claude` when it is too old to start a turn, checked before each one (spec 27); `nil` lets it
    /// start. By default nothing is checked here: the bridge still checks at `init`.
    @ObservationIgnored var outdatedClaude: () async -> String? = { nil }
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
    static func makeDefault(alerts: WaitingAlerts, index: SearchIndex?,
                            bridge: @escaping () async throws -> AgentBridge) throws -> SessionStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let store = SessionStore(file: support.appending(path: "Bubo/Sessioni.json"), worktrees: try .makeDefault(),
                                 orb: .shared, alerts: alerts, ledger: try .makeDefault(),
                                 drafts: DraftStore(file: support.appending(path: "Bubo/Bozze.json")), bridge: bridge)
        store.indexer = index.map { ConversationIndexer(index: $0, bridge: bridge) }
        return store
    }

    /// The configuration `claude` loads in `project`, read through the Sessioni's bridge without spending Quota.
    func configuration(of project: URL) async throws -> ClaudeConfiguration {
        try await configurationSpare.configuration(of: project) { try await bridge().configuration(of: $0) }
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
    ///   - issue: The issue the Sessione starts from, with ⌘I.
    /// - Returns: The id of the new Sessione.
    /// - Throws: `SessionError.checkoutTaken` when `onCheckout` and another open Sessione already works there.
    @discardableResult
    func start(_ prompt: String, title: String, branch: String, in project: URL, onCheckout: Bool = false,
               forkingFrom conversation: CLIConversation? = nil, issue: IssueLink? = nil) throws -> UUID {
        if onCheckout, let taken = checkoutSession(of: project) { throw SessionError.checkoutTaken(by: taken.title) }
        var session = Session(id: UUID(), title: title, project: project, activitySince: .now)
        session.prompt = prompt
        session.forkedFrom = conversation?.id
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

    /// Asks `claude` the first prompt of the open Sessione `id` again, in its copy and in a new Conversazione, once
    /// the turn in progress, if any, is interrupted: Riprova of the onboarding (spec 26).
    func restart(_ id: UUID) {
        guard let prompt = sessions.first(where: { $0.id == id })?.prompt else { return }
        restart(id, prompt: prompt)
    }

    /// Riavvia of a Sessione pesante: interrupts the turn in progress and asks its prompt again in a new `claude`,
    /// in the same copy and in a new Conversazione. Nothing when ``canRestartTurn(_:)`` is false.
    func restartTurn(_ id: UUID) {
        guard canRestartTurn(id), let prompt = turnPrompts[id] else { return }
        restart(id, prompt: prompt)
    }

    /// Whether Riavvia can start the turn in progress of the Sessione `id` again: not while it resolves conflicts.
    func canRestartTurn(_ id: UUID) -> Bool {
        turnPrompts[id] != nil && sessions.first { $0.id == id }?.resolution == nil
    }

    /// Asks `claude` `prompt` in the open Sessione `id`, once the turn in progress, if any, is interrupted.
    private func restart(_ id: UUID, prompt: String) {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta else { return }
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

    /// The open Sessione that works on the checkout of `project`, if any.
    func checkoutSession(of project: URL) -> Session? {
        sessions.first { session in
            session.isOnCheckout && session.phase == .aperta
                && session.project.standardizedFileURL.path == project.standardizedFileURL.path
        }
    }

    /// Asks `claude` again, in the same worktree, the prompt of a Sessione that Bubo's quitting interrupted.
    // ponytail: the same prompt in a new Conversazione; the SDK's `resume` comes with #159.
    func resume(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.isInterrupted, let prompt = session.prompt
        else { return }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.isInterrupted = false
        }
        turnTasks[id] = Task { await run(id, prompt: prompt, branch: session.branchToPrepare) }
    }

    /// Riprova on a Sessione whose turn did not start, because its Sandbox could not or `claude` was too old: the same
    /// turn again, with the Sandbox as the Progetto has it now. Nothing for any other Sessione.
    func retry(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta,
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
        guard let session = sessions.first(where: { $0.id == id }), !session.isRunning, session.phase == .aperta,
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
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta, !session.isRunning
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
        guard session.phase == .aperta else { return nil }
        if !FileManager.default.fileExists(atPath: session.project.path) {
            return String(localized: "Il Progetto non è più in \(session.project.path). Riporta lì la cartella o cancella la Sessione.")
        }
        if let workspace = session.workspace, workspace.branch != nil,
           !FileManager.default.fileExists(atPath: workspace.folder.path) {
            return String(localized: "La copia isolata della Sessione non è più in \(workspace.folder.path). Cancella la Sessione per toglierla dall'elenco.")
        }
        return nil
    }

    /// Prepares the Sessione's copy on `branch` if it has none yet, then asks `claude` `prompt` there.
    ///
    /// - Parameter reopening: The copy of the Archiviata Sessione that Riprendi prepares again, in place of a new one.
    /// - Returns: Whether the turn ended without errors.
    @discardableResult
    private func run(_ id: UUID, prompt: String, branch: String, reopening: Workspace? = nil) async -> Bool {
        guard let session = sessions.first(where: { $0.id == id }) else { return false }
        let environment = session.portEnvironment
        do {
            // Before the copy and the prompt: a `claude` too old starts nothing.
            if let version = await outdatedClaude() { throw AgentBridgeError.claudeOutdated(version: version) }
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
            let classifier = RiskClassifier(workingDirectory: workspace.folder)
            let isSandboxed = sandbox.isEnabled(in: session.project)
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
            previewOffers[id] = (answerID, hasServer)
            defer {
                turns[id] = nil
                turnPrompts[id] = nil
                footprints.forget(id)
                sandboxedTurns[id] = nil
                previewOffers[id] = nil
                permissions.clear(id)
            }
            // Each turn is a conversation of its own, which Bubo keeps (ADR 0006).
            let conversation = UUID().uuidString.lowercased()
            update(id) { $0.conversations.append(conversation) }
            // Also after an error: what was said enters the Indice.
            defer { Task { [indexer, project = session.project] in await indexer?.add(conversation, in: project) } }
            let answer = agent.ask(prompt, in: workspace.folder, environment: environment,
                                   forkingFrom: session.forkedFrom, keeping: conversation,
                                   isSandboxed: isSandboxed, sandboxAllowances: sandbox.allowances(in: session.project),
                                   permissionMode: permissionMode, id: answerID,
                                   offersPreview: hasServer) { [weak self] progress in
                switch progress {
                case .ranCommand: self?.servers.notice()
                case let .variante(nome): self?.orb?.showWork(nome)
                case let .sandboxBlock(block): self?.record(block, in: id)
                case .read: self?.onFileActivity?(id, progress)
                case .edit:
                    self?.update(id) { $0.apply(progress) }
                    self?.onFileActivity?(id, progress)
                default: self?.update(id) { $0.apply(progress) }
                }
            } permissions: { [weak self] event in
                self?.receive(event, in: id, from: agent, classifier: classifier)
            } usage: { [ledger] usage in
                ledger.record(usage, turn: conversation, session: id, project: session.project)
            } preview: { [weak self] action in
                await self?.drivePreview(action, in: id) ?? .failure("Bubo non pilota più questa Sessione.")
            } isDangerous: { request in
                let risk = classifier.risk(of: request)
                return risk.level.isDangerous || risk.isCritical
            }
            var hasAnswered = false
            for try await _ in answer where !hasAnswered {
                hasAnswered = true
                onFirstToken()
            }
            update(id) { $0.enter(.ferma) }
            return true
        } catch {
            Logger.sessions.error("Sessione failed: \(String(describing: error), privacy: .private)")
            onTurnFailure(id, error)
            update(id) { session in
                session.enter(.errore)
                switch error {
                case AgentBridgeError.sandboxUnavailable, AgentBridgeError.claudeOutdated:
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
                case let AgentBridgeError.sandboxUnavailable(reason):
                    String(localized: "Sandbox non disponibile: \(reason). La Sessione non è partita.")
                case let AgentBridgeError.claudeOutdated(version?):
                    String(localized: "Claude Code \(version) è troppo vecchio per Bubo. Aggiornalo e la Sessione parte da sola.")
                case AgentBridgeError.claudeOutdated:
                    String(localized: "Claude Code è troppo vecchio per Bubo. Aggiornalo e la Sessione parte da sola.")
                case QuestionFailure.claudeMissing: String(localized: "Claude Code non trovato: installa la CLI claude.")
                default: String(localized: "Il collegamento con Claude si è interrotto.")
                }
            }
            if case let AgentBridgeError.claudeOutdated(version) = error {
                awaitingClaudeUpdate.insert(id)
                onClaudeOutdated(version)
            }
            return false
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

    /// Whether a Sessione of the Progetto at `project` is in a turn: Bubo then never writes in its memory.
    func isInTurn(_ project: URL) -> Bool {
        sessions.contains { $0.project == project && $0.isRunning }
    }

    /// Annulla of the line Ricordato `line` of the Sessione `id`: puts the memory file back as it was before the write.
    ///
    /// - Throws: ``ProjectMemoryError/inTurn`` while a Sessione of the Progetto is in a turn,
    ///   ``ProjectMemoryError/changedOnDisk`` when the file changed after the write, or another error of
    ///   ``MemoryWrite/undo(in:)``. The line stays as it was then.
    func undo(_ line: MemoryLine.ID, in id: UUID) throws {
        guard let session = sessions.first(where: { $0.id == id }),
              let memoryLine = session.memoryLines.first(where: { $0.id == line }), memoryLine.canUndo,
              case let .remembered(write) = memoryLine.event
        else { return }
        guard !isInTurn(session.project) else { throw ProjectMemoryError.inTurn }
        try write.undo(in: ProjectMemory.directory(ofProject: session.project))
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

    /// Keeps `block` among the latest of the Sessione `id`, once.
    private func record(_ block: SandboxBlock, in id: UUID) {
        var blocks = sandboxBlocks[id] ?? []
        blocks.removeAll { $0 == block }
        blocks.append(block)
        sandboxBlocks[id] = Array(blocks.suffix(Self.sandboxBlockLimit))
    }

    /// Queues a Richiesta di permesso of the Sessione `id`, or answers it at once: no to a critical path,
    /// yes to what the user already allowed "Per questa Sessione".
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
        case let .withdrawn(request):
            permissions.withdraw(request, in: id)
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

    /// Gives the Orb the Stato of the Sessioni's Attività, and tells the user which ones wait.
    private func followActivity() {
        let state = OrbState(following: sessions)
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
    // ponytail: the HUD has no Sessione in front of the user yet; then the Stato follows that one alone.
    init(following sessions: [Session]) {
        let open = sessions.filter { $0.phase == .aperta }
        if open.contains(where: { $0.activity == .attende }) {
            self = .listening
        } else if open.contains(where: { $0.activity == .lavora }) {
            self = .working
        } else {
            self = .idle
        }
    }
}
