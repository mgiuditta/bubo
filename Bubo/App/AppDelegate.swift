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
    /// The folder of notes the Indice follows, chosen in the settings.
    private(set) lazy var secondBrain = SecondBrain(index: searchIndex)
    /// The Domanda of the HUD, answered through the agent bridge.
    private(set) lazy var questions = QuestionModel(index: searchIndex, secondBrain: secondBrain)
    /// The Sessioni, sharing the Domanda's bridge to `claude`; `nil` when Application Support is unavailable.
    private(set) lazy var sessions: SessionStore? = {
        do {
            let alerts = WaitingAlerts(isSeen: { [hud] in hud.isFrontmost }, announce: notifier.announce,
                                       withdraw: notifier.withdraw)
            return try SessionStore.makeDefault(alerts: alerts) { [questions] in try await questions.readyBridge() }
        } catch {
            Logger.sessions.error("Sessioni unavailable: \(error)")
            return nil
        }
    }()
    /// The first launch in the HUD: the first Sessione starts from there, and its first token ends it.
    private(set) lazy var onboarding: OnboardingFlow = {
        let flow = OnboardingFlow(hasSessions: sessions?.sessions.isEmpty == false,
                                  moveToAPIKey: { [weak self] in self?.questions.moveToAPIKey() }) { [weak self] question, project in
            guard let sessions = self?.sessions else { throw CocoaError(.fileWriteUnknown) }
            let title = Session.proposedTitle(for: question)
            // In a folder not trusted yet `claude` loads only the user's settings (#266): no dialog in the onboarding.
            try sessions.start(question, title: title, branch: Session.proposedBranch(for: title), in: project)
        }
        sessions?.onFirstToken = { [weak flow] in flow?.receiveFirstToken() }
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
    /// The global shortcut; created at launch so it works with no window open.
    private(set) lazy var hotKeys = HotKeyCenter { [hud] in hud.toggle() }

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

    private func makeLaunchSequence() -> LaunchSequence {
        LaunchSequence { [questions] in
            await questions.startBridge()
        } isOnboarding: { [weak self] in
            self?.onboarding.isCompleted == false
        } detectClaude: { [weak self] in
            await self?.onboarding.detectClaude()
        } keepIndexFresh: { [searchIndex, secondBrain] in
            secondBrain.start()
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
        notifier.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.apply(isVisible: UserDefaults.standard.bool(forKey: DockIcon.defaultsKey))
        _ = hotKeys
        // Before any turn can start, so the first token reaches it.
        _ = onboarding
        sessions?.onFileActivity = { [weak self] id, progress in self?.galaxies.record(progress, by: id) }
        // Opening the HUD reads the Quota, never its appearance at launch: that would start a `claude` (spec 25).
        hud.didShow = { [weak self] in
            Task { await self?.questions.readQuotaIfNeeded() }
        }
        // The same SwiftUI menu as the menu bar's, so the two never drift apart.
        let menu = NSHostingMenu(rootView: MenuBarContent()
            .environment(hud)
            .environment(hotKeys)
            .environment(panel))
        panel.start(openingHUD: { [hud] in hud.show() }, menu: menu)
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
