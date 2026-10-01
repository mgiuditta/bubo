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
    /// The notifications of the Sessioni in Attende te; a click opens the HUD, Solo ora and No answer from there.
    private lazy var notifier = Notifier { [hud] in hud.show() } answer: { [weak self] request, session, allows in
        self?.sessions?.answerFromNotification(request, in: session, allows: allows)
    }
    /// The Galassia windows, one per Progetto.
    private(set) lazy var galaxies = GalaxyStore { [weak self] in
        self?.sessions?.projects ?? []
    } viewer: { [weak self] in
        self?.sessions?.viewer
    }
    /// The global shortcut; created at launch so it works with no window open.
    private(set) lazy var hotKeys = HotKeyCenter { [hud] in hud.toggle() }

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
        Task(priority: .utility) { [searchIndex] in await searchIndex?.keepFresh() }
        secondBrain.start()
        // The copy of the Cronologia CLI waits for the launch to settle: it starts the bridge.
        Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            await self?.sessions?.keepCLIHistoryFresh()
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
