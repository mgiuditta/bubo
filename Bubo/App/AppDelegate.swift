import AppKit
import os
import SwiftUI

/// Owns the app-wide services that must exist before any window appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shows and hides the HUD.
    let hud = HUDPresenter()
    /// The always-on-top Panel with the Orb.
    let panel = OrbPanelController()
    /// The pairing of the Telecomando, in Impostazioni › iPhone (spec 21).
    let remote = PairingController.live()
    /// The Progetti whose Sessioni never reach the iPhone, in Impostazioni › iPhone.
    let macOnlyProjects = MacOnlyProjects()
    /// Lets the Sessioni and the Battito out to the paired iPhones.
    private(set) lazy var remoteBridge = RemoteBridge.live(remote: remote, macOnly: macOnlyProjects, sessions: sessions)
    /// Whether the user is at the Mac: then a Richiesta reaches the iPhone without a notification.
    let presence = PresenceMonitor()
    /// Sends the Richieste di permesso to the paired iPhones and answers them with their Verdicts.
    private(set) lazy var remoteRequests = RemoteRequests.live(remote: remote, macOnly: macOnlyProjects, presence: presence)
    /// Keeps the iPhones up to date while Bubo runs.
    private var remoteUpdates: Task<Void, Never>?
    /// This Macchina's key and the Biglietti of the Consegne, in Impostazioni › Consegne (spec 24).
    let deliveries = DeliveriesController.live()
    /// The Indice, kept fresh while Bubo runs; `nil` when its database cannot be opened.
    let searchIndex: SearchIndex? = {
        do {
            return try SearchIndex.makeDefault()
        } catch {
            Logger.index.error("Indice unavailable: \(error)")
            return nil
        }
    }()
    /// The search by meaning of the Indice, once its model is downloaded.
    private(set) lazy var semanticSearch = SemanticSearch(index: searchIndex, store: try? TextEmbeddingModelStore.makeDefault())
    /// The folder of notes the Indice follows, chosen in the settings.
    private(set) lazy var secondBrain = SecondBrain(index: searchIndex)
    /// The record of every turn, of the Sessioni and of the Domande; in memory only when Application Support is
    /// unavailable.
    let ledger: CostLedger = {
        do {
            return try CostLedger.makeDefault()
        } catch {
            Logger.costs.error("Costi kept in memory: \(error)")
            return CostLedger()
        }
    }()
    /// The Domanda of the HUD, answered through the agent bridge.
    private(set) lazy var questions = QuestionModel(index: searchIndex, secondBrain: secondBrain, ledger: ledger)
    /// Refreshes the PriceTable, at most once a day.
    private var priceUpdates: Task<Void, Never>?
    /// Checks the updates of every Marketplace's plugins, once a day, with the Plugin window closed too.
    private let pluginUpdates = PluginUpdateScheduler(checker: .live())
    /// The Sessioni, sharing the Domanda's bridge to `claude`; `nil` when Application Support is unavailable.
    private(set) lazy var sessions: SessionStore? = {
        do {
            let alerts = WaitingAlerts(isSeen: { [hud] in hud.isFrontmost }, announce: notifier.announce,
                                       withdraw: notifier.withdraw)
            let store = try SessionStore.makeDefault(alerts: alerts, index: searchIndex, ledger: ledger) { [questions] in try await questions.readyBridge() }
            // Passa all'abbonamento at 100% of a Budget moves the Domande too: one bridge, one credential.
            store.moveToSubscription = { [questions] in questions.moveToSubscription() }
            return store
        } catch {
            Logger.sessions.error("Sessioni unavailable: \(error)")
            return nil
        }
    }()
    /// The Riassunti di Sessione, written in the Secondo cervello at Fondi and Archivia; `nil` without Sessioni.
    private(set) lazy var summarizer: SessionSummarizer? = makeSummarizer()
    /// Writes the pending Riassunti di Sessione each time the network returns.
    private var summaryRetries: Task<Void, Never>?
    /// What starts the Esecuzioni of the Automazioni; `nil` without the Sessioni.
    private(set) lazy var executions: ExecutionRunner? = sessions.map { sessions in
        let runner = ExecutionRunner(automations: sessions.automations, sessions: sessions)
        runner.onFinish = { [notifier] automation, execution in
            Task { await notifier.announceResult(of: execution, from: automation) }
        }
        return runner
    }
    /// Starts the Esecuzioni at the times of their Ripetizioni; `nil` without the Sessioni.
    private lazy var scheduler: AutomationScheduler? = sessions.flatMap { sessions in
        executions.map { runner in
            let scheduler = AutomationScheduler(automations: sessions.automations, runner: runner)
            scheduler.onRecovery = { [notifier] automation, scheduledAt in
                Task { await notifier.announceRecovery(of: automation, scheduledAt: scheduledAt) }
            }
            return scheduler
        }
    }
    /// Removes the worktrees that a crash left to the Esecuzioni; `nil` without the Sessioni.
    private lazy var sweeper: WorktreeSweeper? = sessions.map { WorktreeSweeper(automations: $0.automations, sessions: $0) }
    /// The first launch in the HUD: the first Sessione starts from there, and its first token ends it.
    private(set) lazy var onboarding: OnboardingFlow = {
        let flow = OnboardingFlow(hasSessions: sessions?.sessions.isEmpty == false,
                                  moveToAPIKey: { [weak self] in self?.questions.moveToAPIKey() },
                                  moveToSubscription: { [weak self] in self?.questions.moveToSubscription() },
                                  restart: { [weak self] session in self?.sessions?.restart(session) }) { [weak self] question, project in
            guard let sessions = self?.sessions else { throw CocoaError(.fileWriteUnknown) }
            let title = Session.proposedTitle(for: question)
            // In a folder not trusted yet `claude` loads only the user's settings (#266): no dialog in the onboarding.
            return try sessions.start(question, title: title, branch: Session.proposedBranch(for: title), in: project)
        }
        sessions?.onFirstToken = { [weak flow] in flow?.receiveFirstToken() }
        sessions?.onTurnFailure = { [weak flow] session, error in flow?.receiveFailure(error, in: session) }
        // A `claude` too old stops the Sessione before its prompt and shows the remedy; once updated, it starts.
        sessions?.outdatedClaude = { await ClaudeReadiness.outdatedVersion() }
        sessions?.onClaudeOutdated = { [weak flow] version in flow?.readiness = .outdated(version: version ?? "") }
        flow.onClaudeReady = { [weak self] in self?.sessions?.startTurnsAwaitingUpdate() }
        return flow
    }()
    /// The notifications of the Sessioni in Attende te; a click opens the HUD, Solo ora and No answer from there.
    private lazy var notifier = Notifier { [hud] session in
        if let session { hud.show(session: session) } else { hud.show() }
    } answer: { [weak self] request, session, allows in
        self?.sessions?.answerFromNotification(request, in: session, allows: allows)
    }
    /// The notifications of a Budget past its threshold, read at each turn the ledger records.
    private lazy var budgetAlerts = BudgetAlerts(ledger: ledger) { [notifier] status in await notifier.announce(status) }
    /// The Galassia windows, one per Progetto.
    private(set) lazy var galaxies = GalaxyStore { [weak self] in
        self?.sessions?.projects ?? []
    } sessions: { [weak self] in
        self?.sessions?.sessions ?? []
    } viewer: { [weak self] in
        self?.sessions?.viewer
    } sessionStore: { [weak self] in
        self?.sessions
    }
    /// What starts once the HUD is interactive: the only place for work after launch.
    private(set) lazy var launch = makeLaunchSequence()
    /// The Palette, opened with ⌘K: the past conversations, searched in the Indice.
    private(set) lazy var palette: PaletteWindow = PaletteWindow(search: { [weak self] in
        ConversationSearch(index: self?.searchIndex, sessions: self?.sessions?.sessions ?? [],
                           history: self?.sessions?.lastHistory ?? [])
    }, actions: resumeActions) { [weak self] result in
        self?.history.show(result, searching: self?.palette.searchedText ?? "")
    }
    /// The Cronologia window: the past conversations, read only on the message found.
    private(set) lazy var history: HistoryWindow = HistoryWindow(search: { [weak self] in
        ConversationSearch(index: self?.searchIndex, sessions: self?.sessions?.sessions ?? [],
                           history: self?.sessions?.lastHistory ?? [])
    }, read: { [sessions] conversation in
        guard let sessions else { throw CocoaError(.fileReadUnknown) }
        return try await sessions.transcript(ofConversation: conversation)
    }, actions: resumeActions)
    /// The Costi window: the CostLedger's turns by Progetto, Sessione, model, provider and period.
    private(set) lazy var costs = CostsWindow(ledger: ledger) { [weak self] id in
        self?.sessions?.sessions.first { $0.id == id }?.title
    }
    /// Riprendi and Continua da qui, from the Palette and the Cronologia window.
    private(set) lazy var resumeActions = ResumeActions(sessions: { [weak self] in self?.sessions }, hud: hud)
    /// The global shortcut; created at launch so it works with no window open.
    private(set) lazy var hotKeys = HotKeyCenter { [pushToTalk] in pushToTalk.press(sending: $0) } release: { [pushToTalk] in pushToTalk.release() }
    /// The global shortcut held down: dictation into the Domanda, sent at release unless it was the sola dettatura.
    private(set) lazy var pushToTalk = PushToTalk(listener: SpeechListener()) { [questions] in
        questions.stopSpeaking()
    } tap: { [hud] in hud.toggle() } show: { [hud] in
        hud.show()
    } dictate: { [questions] text, sends in
        questions.prompt = text
        if sends { questions.askByVoice() }
    } predict: { [questions] text in
        questions.predict(text)
    }

    /// Shows the standard About panel, with Bubo's one line of credits.
    func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: String(localized: "Per chi disegna orbite."), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func makeSummarizer() -> SessionSummarizer? {
        guard let sessions else { return nil }
        let claude = ClaudeSummaryEngine(bridge: { [questions] in try await questions.readyBridge() },
                                         usage: { usage, id, turn in
            guard let project = sessions.sessions.first(where: { $0.id == id })?.project else { return }
            sessions.ledger.record(usage, turn: turn, session: id, project: project)
        })
        let engines: [any SummaryEngine] = [claude, FoundationModelsSummaryEngine()]
        return SessionSummarizer(sessions: sessions, secondBrain: secondBrain, index: searchIndex, engines: engines,
                                 transcript: { conversation in try await sessions.transcript(ofConversation: conversation) })
    }

    private func makeLaunchSequence() -> LaunchSequence {
        LaunchSequence { [questions] in
            await questions.startBridge()
        } isOnboarding: { [weak self] in
            self?.onboarding.isCompleted == false
        } detectClaude: { [weak self] in
            await self?.onboarding.detectClaude()
        } keepIndexFresh: { [searchIndex, secondBrain, semanticSearch] in
            secondBrain.start()
            semanticSearch.start()
            await withDiscardingTaskGroup { group in
                group.addTask { await searchIndex?.keepFresh() }
                group.addTask { await semanticSearch.followPauses() }
            }
        } subscribeToMetrics: {
            MetricsCollector.shared.subscribe()
        } startConfigurationSpare: { [weak self] in
            self?.sessions?.configurationSpare.startAfterLaunch()
        } keepCLIHistoryFresh: { [weak self] in
            await self?.sessions?.keepCLIHistoryFresh()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before the first frame, or MetricKit refuses to extend the launch.
        MetricsCollector.shared.extendLaunch()
        FontRegistry.registerBundledFonts()
        UserDefaults.standard.register(defaults: [DockIcon.defaultsKey: true, ConversationStore.keepsCLIHistoryKey: true])
        // Before any App Intent runs: "Chiedi a Bubo" asks the Domanda of the HUD.
        AskBuboIntent.questions = questions
        // "Apri Galassia" opens the Galassia windows; with one in focus, the Orb follows its filtered Sessione.
        OpenGalaxyIntent.galaxies = galaxies
        // "Cerca nella cronologia" opens the Palette, as ⌘K does.
        SearchHistoryIntent.palette = self
        galaxies.focusOrb = { [weak self] id in self?.sessions?.orbFocus = id }
        // At once, within the turn that passes a Budget's threshold.
        ledger.didRecord = { [weak self] entry in self?.budgetAlerts.check(after: entry) }
        hud.showInGalaxy = { [galaxies] session in galaxies.show(session) }
        // "Nuova Sessione" starts its Sessioni in the HUD's store; the Domanda proposes them on the same Progetti.
        if let sessions {
            NewSessionIntent.starter = IntentSessionStarter(store: sessions, hud: hud, panel: panel)
            questions.knownProjects = { [weak sessions] in sessions?.projects ?? [] }
        }
        hud.attachToQuestion = { [questions] attachments in questions.attach(attachments) }
        notifier.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.apply(isVisible: UserDefaults.standard.bool(forKey: DockIcon.defaultsKey))
        _ = hotKeys
        // Before any turn can start, so the first token reaches it.
        _ = onboarding
        sessions?.onFileActivity = { [weak self] id, progress in self?.galaxies.record(progress, by: id) }
        // The Ripetizioni of the Automazioni; an Esecuzione left in corso at quitting becomes Interrotta.
        scheduler?.start()
        sweeper?.start()
        // Before any Fondi or Archivia, so their summaries start; the pending ones are written once online.
        summaryRetries = Task { [summarizer] in await summarizer?.keepRetrying() }
        remoteUpdates = Task { [remote, remoteBridge, remoteRequests, presence, sessions] in
            await remote.loadDevices()
            guard let sessions else { return await remoteBridge.cleanUp() }
            async let presenceChanges: Void = presence.run()
            async let requests: Void = remoteRequests.run(sessions: sessions)
            await remoteBridge.run(sessions: sessions)
            _ = await (presenceChanges, requests)
        }
        // The feature's only network call, away from the launch; `updateIfDue` lets it through once a day.
        priceUpdates = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await PriceTable.shared.updateIfDue()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
        pluginUpdates.start()
        // Opening the HUD reads the Quota, never its appearance at launch: that would start a `claude` (spec 25).
        hud.didShow = { [weak self] in
            Task { await self?.questions.readQuotaIfNeeded() }
        }
        // The same SwiftUI menu as the menu bar's, so the two never drift apart.
        let menu = NSHostingMenu(rootView: MenuBarContent(sessions: sessions, questions: questions)
            .environment(hud)
            .environment(hotKeys)
            .environment(panel))
        panel.start(openingHUD: { [hud] in hud.show() }, menu: menu, questions: questions, hud: hud)
        hud.searchConversations = { [weak self] text in self?.palette.show(text: text) }
        hud.showCosts = { [weak self] in self?.costs.show() }
    }

    /// Back in front: the pull requests are read at once, then at intervals (spec 16).
    func applicationDidBecomeActive(_ notification: Notification) {
        sessions?.followPullRequests(isForeground: true)
    }

    /// In the background: no reading of the pull requests, so no `gh` runs.
    func applicationDidResignActive(_ notification: Notification) {
        sessions?.followPullRequests(isForeground: false)
    }

    /// `bubo://draft` links, and `bubo://linear` from Linear's custom script, also with Bubo closed: each valid one
    /// becomes a Bozza, or leads to the one its issue already has; then the HUD shows the Board. `bubo://sessione`
    /// shows its Sessione. A link never starts a Sessione: anyone can write one.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        for file in files {
            Task { await open(bubo: file) }
        }
        guard let sessions else { return }
        var madeDrafts = false
        for url in urls where !url.isFileURL {
            if let link = SessionLink(url) {
                show(link, among: sessions.sessions)
            } else if let link = LinearLink(url) {
                receive(link, in: sessions)
                madeDrafts = true
            } else if let link = DraftLink(url) {
                sessions.receive(link)
                madeDrafts = true
            } else {
                Logger.sessions.error("Link not valid: \(url.absoluteString, privacy: .private)")
            }
        }
        if madeDrafts { hud.showDrafts() }
    }

    /// A `.bubo` file opened from the Finder: a Biglietto shows its code in the HUD; a Consegna, or a file that does
    /// not open, an alert.
    private func open(bubo file: URL) async {
        let message: String
        switch await deliveries.open(file) {
        case .ticket:
            hud.show()
            return
        case .consegna:
            message = String(localized: "Questa versione di Bubo non apre ancora le Consegne. Aggiorna Bubo, poi riaprila.")
        case .failed(.unsupportedVersion):
            message = String(localized: "Il file è di una versione più nuova di Bubo. Aggiorna Bubo, poi riaprilo.")
        case .failed(.notBubo), .failed(.unreadable):
            message = String(localized: "Il file non è un file Bubo, oppure non si legge.")
        case .failed:
            message = String(localized: "Il Biglietto è stato modificato o è danneggiato. Chiedi di rimandarlo.")
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Non si apre")
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    /// A Sessione's link: the HUD on it while it lives, else the Cronologia window on its latest conversation.
    private func show(_ link: SessionLink, among sessions: [Session]) {
        switch link.destination(among: sessions) {
        case .hud(let id):
            hud.show(session: id)
        case .history(let result):
            history.show(result, searching: "")
        case .unavailable:
            Logger.sessions.error("Link to a Sessione Bubo does not have: \(link.id, privacy: .private)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Sessione non più disponibile")
            alert.informativeText = String(localized: "La Sessione di questo link è stata cancellata o non si trova su questo Mac.")
            NSApp.activate()
            alert.runModal()
        }
    }

    /// A Linear issue: a Bozza on the Progetto of the folder chosen in Linear, else on the one chosen before for its
    /// team; else Bubo asks for the folder and remembers it for the team. Annulla makes no Bozza.
    private func receive(_ link: LinearLink, in sessions: SessionStore) {
        if let project = sessions.project(for: link) {
            sessions.receive(link, in: project)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = link.workDirectory
        panel.message = String(localized: "In quale Progetto lavori sulle issue \(link.team) di Linear? Bubo lo ricorderà.")
        panel.prompt = String(localized: "Usa questo Progetto")
        NSApp.activate()
        guard panel.runModal() == .OK, let project = panel.url else { return }
        sessions.remember(project, forTeamOf: link)
        sessions.receive(link, in: project)
    }

    /// ⌘K: shows the Palette, or closes it. The first time, the Cronologia CLI is read for its titles.
    func togglePalette() {
        palette.toggle()
        readCLIHistoryIfNeeded()
    }

    /// Reads the Cronologia CLI for its titles when the Palette is shown and it was never read.
    private func readCLIHistoryIfNeeded() {
        if let sessions, sessions.lastHistory.isEmpty, palette.isShown {
            Task { [palette] in
                _ = try? await sessions.history(isComplete: true)
                await palette.refresh()
            }
        }
    }

    /// ⌃`: shows or hides the terminal of the current Sessione, in the HUD unless it was detached.
    func toggleTerminal() {
        guard let sessions else { return }
        sessions.terminals.toggle(sessions.terminalSession)
        if sessions.terminals.isShown && !sessions.terminals.isDetached { hud.show() }
    }

    /// ⌘⇧P: shows or hides the Anteprima of the current Sessione, in the HUD unless it was detached; with no server,
    /// nothing.
    func togglePreview() {
        guard let sessions else { return }
        sessions.togglePreview()
        if sessions.previews.isShown && !sessions.previews.isDetached { hud.show() }
    }

    /// ⌥⌘G: shows the Galassia of the current Sessione's Progetto, else of the most recent one; with no Progetto,
    /// asks for a folder.
    func showGalaxy() {
        if let project = sessions?.terminalSession?.project ?? sessions?.projects.first {
            galaxies.show(project)
        } else {
            galaxies.chooseFolder()
        }
    }

    /// Quitting closes the terminals: when something runs in them, only after a confirmation that lists it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = sessions?.terminals.runningCommands ?? []
        guard !running.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Vuoi uscire da Bubo?")
        alert.informativeText = String(localized: "Nel terminale si fermano: \(running.formatted()).")
        alert.addButton(withTitle: String(localized: "Esci"))
        alert.addButton(withTitle: String(localized: "Annulla"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessions?.terminals.closeAllBeforeQuitting()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { hud.show() }
        return true
    }
}

extension AppDelegate: HistorySearching {
    /// Shows the Palette on the recent conversations, for "Cerca nella cronologia".
    func searchHistory() {
        palette.show()
        readCLIHistoryIfNeeded()
    }
}
