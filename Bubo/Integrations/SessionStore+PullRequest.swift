import Foundation

extension SessionStore {
    /// The Sessione Apri PR… in the menu and the Palette opens the sheet for: among the Aperta ones with a branch of
    /// their own and the agent still, the one whose terminal is shown, else the one that changed Attività last.
    var pullRequestSessionToOpen: Session? {
        current(among: sessions.filter { session in
            session.phase == .aperta && !session.isRunning && !session.isOnCheckout && session.resolution == nil
                && session.workspace?.branch != nil && session.pullRequest == nil
        })
    }

    /// The Sessione Aggiorna PR in the menu and the Palette pushes: among those In revisione with work their pull
    /// request lacks and the agent still, the one whose terminal is shown, else the one that changed Attività last.
    var pullRequestSessionToUpdate: Session? {
        current(among: sessions.filter { session in
            session.phase == .inRevisione && !session.isRunning
                && pullRequests.statuses[session.id]?.isBehind == true
                && !pullRequests.updating.contains(session.id)
        })
    }

    private func current(among candidates: [Session]) -> Session? {
        if let shown = terminals.session, let session = candidates.first(where: { $0.id == shown.id }) {
            return session
        }
        return candidates.max { ($0.activitySince ?? .distantPast) < ($1.activitySince ?? .distantPast) }
    }
}
