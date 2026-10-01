import Foundation

extension SessionStore {
    /// The Sessione whose Anteprima ⌘⇧P opens, among the open ones with a server: the one shown last, else the one
    /// whose terminal is shown, else the one that changed Attività most recently; `nil` when none has a server.
    var previewSession: Session? {
        let candidates = sessions.filter { $0.phase == .aperta && servers.servers[$0.id]?.isEmpty == false }
        for id in [previews.sessionID, terminals.session?.id].compactMap(\.self) {
            if let session = candidates.first(where: { $0.id == id }) { return session }
        }
        return candidates.max { ($0.activitySince ?? .distantPast) < ($1.activitySince ?? .distantPast) }
    }

    /// Shows the Anteprima of `session`; nothing happens while it has no server.
    func showPreview(of session: Session) {
        guard session.phase == .aperta else { return }
        previews.show(session, servers: servers.servers[session.id] ?? [])
    }

    /// ⌘⇧P: hides the Anteprima when it shows, else shows the one of ``previewSession``; with no server, nothing.
    func togglePreview() {
        if previews.isShown {
            previews.hide()
        } else if let session = previewSession {
            showPreview(of: session)
        }
    }

    /// Does what the agent of the Sessione `id` asks of its Anteprima, opening the page if the user never did.
    func drivePreview(_ action: PreviewAction, in id: UUID) async -> PreviewReply {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta,
              let sockets = servers.servers[id], !sockets.isEmpty
        else { return .failure("La Sessione non ha un server in ascolto: l'Anteprima non è disponibile.") }
        return await PreviewDriver(preview: previews.page(of: session, servers: sockets)).perform(action)
    }
}
