import AppKit
import os
import SwiftUI

/// Owns the app-wide services that must exist before any window appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shows and hides the HUD.
    let hud = HUDPresenter()
    /// The always-on-top Panel with the Orb.
    let panel = OrbPanelController()
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
    /// The Sessioni, sharing the Domanda's bridge to `claude`; `nil` when Application Support is unavailable.
    private(set) lazy var sessions: SessionStore? = {
        do {
            let alerts = WaitingAlerts(isSeen: { [hud] in hud.isFrontmost }, announce: notifier.announce,
                                       withdraw: notifier.withdraw)
            return try SessionStore.makeDefault(alerts: alerts, index: searchIndex, ledger: ledger) { [questions] in try await questions.readyBridge() }
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
    private(set) lazy var executions: ExecutionRunner? = sessions.map { ExecutionRunner(automations: $0.automations, sessions: $0) }
    /// Starts the Esecuzioni at the times of their Ripetizioni; `nil` without the Sessioni.
    private lazy var scheduler: AutomationScheduler? = sessions.flatMap { sessions in
        executions.map { AutomationScheduler(automations: sessions.automations, runner: $0) }
    }
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
    private lazy var notifier = Notifier { [hud] in hud.show() } answer: { [weak self] request, session, allows in
        self?.sessions?.answerFromNotification(request, in: session, allows: allows)
    }
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
            await searchIndex?.keepFresh()
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
        // Before any Fondi or Archivia, so their summaries start; the pending ones are written once online.
        summaryRetries = Task { [summarizer] in await summarizer?.keepRetrying() }
        // The feature's only network call, away from the launch; `updateIfDue` lets it through once a day.
        priceUpdates = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await PriceTable.shared.updateIfDue()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
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
    /// becomes a Bozza, or leads to the one its issue already has; then the HUD shows the Board. A link never starts a
    /// Sessione: anyone can write one.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let sessions else { return }
        for url in urls {
            if let link = LinearLink(url) {
                receive(link, in: sessions)
                continue
            }
            guard let link = DraftLink(url) else {
                Logger.sessions.error("Link not valid: \(url.absoluteString, privacy: .private)")
                continue
            }
            sessions.receive(link)
        }
        hud.showDrafts()
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
