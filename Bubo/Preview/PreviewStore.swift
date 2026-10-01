import Foundation
import os

/// The Anteprime of the Sessioni and the panel that shows one of them (spec 15).
///
/// An Anteprima exists only for a Sessione with a server and opens only with a gesture: a clic on the label
/// `localhost:NNNN` or ⌘⇧P, never on its own.
@Observable
final class PreviewStore {
    /// The Anteprima of each Sessione that opened one, alive with the panel closed.
    private(set) var pages: [UUID: PreviewPage] = [:]
    /// The Sessione whose Anteprima the panel shows.
    private(set) var sessionID: UUID?
    /// The panel's title: the Sessione's.
    private(set) var title = ""
    /// Whether the panel is visible, in the HUD or in its own window.
    private(set) var isShown = false
    /// Whether the panel is in its own window instead of the HUD.
    private(set) var isDetached = false

    /// The panel's own window, once it has been detached.
    @ObservationIgnored private var detachedWindow: PreviewWindow?

    /// The Anteprima the panel shows.
    var shown: PreviewPage? {
        sessionID.flatMap { pages[$0] }
    }

    /// Shows the Anteprima of `session`, served by `servers`, opening it at its first server when it has none yet;
    /// does nothing without a server.
    func show(_ session: Session, servers: [ListeningSocket]) {
        guard !servers.isEmpty else { return }
        page(of: session, servers: servers)
        sessionID = session.id
        title = session.title
        isShown = true
        updateWindow()
    }

    /// The Anteprima of `session`, served by `servers`, opened at its first server when it has none yet; the panel
    /// stays as it is. The agent's tools use it this way, with the panel closed too.
    @discardableResult
    func page(of session: Session, servers: [ListeningSocket]) -> PreviewPage {
        let launchConfigs = session.workspace.map { LaunchConfig.read(in: $0.folder) } ?? []
        let policy = PreviewPolicy(ports: servers.map(\.port), launchConfigs: launchConfigs)
        if let preview = pages[session.id] {
            preview.policy = policy
            return preview
        }
        let preview = PreviewPage(sessionID: session.id, policy: policy)
        preview.serverPIDs = Self.pids(of: servers)
        if let url = policy.startURL { preview.load(url) }
        pages[session.id] = preview
        return preview
    }

    /// Hides the panel; the Anteprime stay open.
    func hide() {
        isShown = false
        updateWindow()
    }

    /// Moves the panel to its own window, or back into the HUD.
    func setDetached(_ isDetached: Bool) {
        self.isDetached = isDetached
        updateWindow()
    }

    /// Follows the Sessioni's servers: an Anteprima closes when its Sessione has none left, and reloads when another
    /// process listens again on the port it shows, as a server that restarted.
    func update(with servers: [UUID: [ListeningSocket]]) {
        for (id, preview) in pages {
            guard let sockets = servers[id], !sockets.isEmpty else {
                close(id)
                continue
            }
            preview.policy.ports = Set(sockets.map(\.port))
            let pids = Self.pids(of: sockets)
            if let port = preview.page.url?.port, let pid = pids[port], let old = preview.serverPIDs[port], pid != old {
                Logger.preview.info("Server back on its port: Anteprima reloaded")
                preview.reload()
            }
            preview.serverPIDs = pids
        }
    }

    /// Closes the Anteprima of the Sessione `id`, when its server goes or at Fondi, Archivia and Cancella; the
    /// Sessione's cookies stay.
    func close(_ id: UUID) {
        guard let preview = pages.removeValue(forKey: id) else { return }
        preview.close()
        if sessionID == id {
            sessionID = nil
            hide()
        }
    }

    /// Shows or hides the detached window to match the panel.
    private func updateWindow() {
        if isShown && isDetached {
            if detachedWindow == nil { detachedWindow = PreviewWindow(store: self) }
            detachedWindow?.show()
        } else {
            detachedWindow?.hide()
        }
    }

    private static func pids(of sockets: [ListeningSocket]) -> [Int: pid_t] {
        Dictionary(sockets.map { ($0.port, $0.pid) }) { first, _ in first }
    }
}
