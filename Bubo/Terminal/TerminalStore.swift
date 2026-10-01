import Foundation
import os

/// The terminals of the Sessioni, in schede, and the panel that shows one Sessione's (spec 15).
///
/// A terminal exists only inside a Sessione that has its own folder: never on the Progetto's checkout, never for a
/// Domanda. Its processes die when Bubo quits, at Archivia and at Fondi.
@Observable
final class TerminalStore {
    /// The schede of each Sessione, in the order they were opened.
    private(set) var tabs: [UUID: [TerminalTab]] = [:]
    /// The scheda in front, by Sessione.
    var selection: [UUID: TerminalTab.ID] = [:]
    /// The Sessione whose terminal the panel shows.
    private(set) var session: Session?
    /// Whether the panel is visible, in the HUD or in its own window.
    private(set) var isShown = false
    /// Whether the panel is in its own window instead of the HUD.
    private(set) var isDetached = false
    /// Why the last scheda did not start.
    private(set) var failure: String?

    /// The shell of new schede and its arguments; the login shell outside tests.
    @ObservationIgnored var shell = (executable: PTYSession.loginShell, arguments: ["-l"])
    /// The panel's own window, once it has been detached.
    @ObservationIgnored private var detachedWindow: TerminalWindow?

    /// The schede of the Sessione `id`.
    func tabs(of id: UUID) -> [TerminalTab] {
        tabs[id] ?? []
    }

    /// ⌃`: hides the panel when it shows, else shows the terminal of `session`.
    func toggle(_ session: Session?) {
        if isShown {
            hide()
        } else if let session {
            show(session)
        }
    }

    /// Shows the terminal of `session`, with a first scheda when it has none.
    func show(_ session: Session) {
        guard session.terminalFolder != nil else { return }
        self.session = session
        if tabs(of: session.id).isEmpty { openTab() }
        isShown = !tabs(of: session.id).isEmpty || failure != nil
        updateWindow()
    }

    /// Hides the panel; the shells keep running.
    func hide() {
        isShown = false
        updateWindow()
    }

    /// Moves the panel to its own window, or back into the HUD.
    func setDetached(_ isDetached: Bool) {
        self.isDetached = isDetached
        updateWindow()
    }

    /// Opens a new scheda in the shown Sessione's folder and brings it to the front.
    func openTab() {
        guard let session, let folder = session.terminalFolder else { return }
        do {
            let tab = try TerminalTab(folder: folder, environment: ChildEnvironment.makeForTerminal(of: session),
                                      shell: shell.executable, arguments: shell.arguments) { [weak self] tab in
                self?.remove(tab, of: session.id)
            }
            tabs[session.id, default: []].append(tab)
            selection[session.id] = tab.id
            failure = nil
        } catch {
            Logger.terminal.error("Terminal not started: \(String(describing: error), privacy: .public)")
            let reason = if case let ProcessSpawnerError.failed(code) = error { String(cString: strerror(code)) }
                         else { error.localizedDescription }
            failure = String(localized: "Il terminale non è partito: \(reason)")
        }
    }

    /// Closes `tab`: its shell and what runs in it are hung up on.
    func close(_ tab: TerminalTab, of id: UUID) {
        remove(tab, of: id)
        Task { await tab.pty.close() }
    }

    /// What runs in the terminals of the Sessione `id` besides their shells, each name once.
    func runningCommands(of id: UUID) -> [String] {
        Self.unique(tabs(of: id).flatMap(\.pty.runningCommands))
    }

    /// What runs in every terminal besides their shells, each name once.
    var runningCommands: [String] {
        Self.unique(tabs.values.flatMap { $0 }.flatMap(\.pty.runningCommands))
    }

    /// Closes the terminals of the Sessione `id`, at Archivia, Fondi and Cancella.
    func closeAll(of id: UUID) async {
        let closing = tabs.removeValue(forKey: id) ?? []
        selection[id] = nil
        if session?.id == id { hide() }
        await PTYSession.stop(closing.flatMap(\.pty.processes))
    }

    /// Closes every terminal before Bubo quits, waiting on the calling thread for the processes to exit.
    func closeAllBeforeQuitting() {
        PTYSession.hangUp(tabs.values.flatMap { $0 }.flatMap(\.pty.processes))
        tabs = [:]
    }

    /// The panel's title: the Sessione's.
    var title: String {
        session?.title ?? String(localized: "Terminale")
    }

    /// Shows or hides the detached window to match the panel.
    private func updateWindow() {
        if isShown && isDetached {
            if detachedWindow == nil { detachedWindow = TerminalWindow(store: self) }
            detachedWindow?.show()
        } else {
            detachedWindow?.hide()
        }
    }

    private func remove(_ tab: TerminalTab, of id: UUID) {
        tabs[id]?.removeAll { $0.id == tab.id }
        if selection[id] == tab.id { selection[id] = tabs[id]?.last?.id }
        if tabs[id]?.isEmpty == true {
            tabs[id] = nil
            if session?.id == id { hide() }
        }
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
