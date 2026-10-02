import Foundation
import os

/// What "Nuova Sessione" starts its Sessioni with: the store of the HUD, the trust of `claude`, the HUD for the trust
/// dialog and the Panel for what went wrong.
final class IntentSessionStarter: SessionStarting {
    private let store: SessionStore
    private let hud: HUDPresenter
    private let panel: OrbPanelController
    private let gate: TrustGate

    init(store: SessionStore, hud: HUDPresenter, panel: OrbPanelController, gate: TrustGate = TrustGate()) {
        self.store = store
        self.hud = hud
        self.panel = panel
        self.gate = gate
    }

    var projects: [URL] { store.projects }

    func isTrusted(_ project: URL) -> Bool {
        gate.isTrusted(project)
    }

    func startSession(_ request: String, in project: URL) throws {
        let title = Session.proposedTitle(for: request)
        try store.start(request, title: title, branch: Session.proposedBranch(for: title), in: project)
    }

    func askTrust(toStart request: String, in project: URL) {
        var draft = SessionDraft(prompt: request)
        draft.project = project
        hud.createSession(from: draft)
    }

    func report(_ message: String) {
        Logger.sessions.info("Nuova Sessione from an intent not started: the Progetto is gone")
        panel.bubble.show(notice: message)
    }
}
