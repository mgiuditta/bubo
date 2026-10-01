import Foundation

extension SessionStore {
    /// The Sessione whose terminal ⌃` opens: the one shown last while it can have one, else the Sessione with a
    /// folder of its own that changed Attività most recently; `nil` when none has one.
    var terminalSession: Session? {
        let candidates = sessions.filter { $0.terminalFolder != nil }
        if let shown = terminals.session, let session = candidates.first(where: { $0.id == shown.id }) {
            return session
        }
        return candidates.max { ($0.activitySince ?? .distantPast) < ($1.activitySince ?? .distantPast) }
    }

    /// What runs in the terminals of the Sessione `id`, said as the line of a confirmation; `nil` when nothing does.
    func terminalNotice(of id: UUID) -> String? {
        let running = terminals.runningCommands(of: id)
        guard !running.isEmpty else { return nil }
        return String(localized: "Nel terminale si fermano: \(running.formatted()).")
    }
}
