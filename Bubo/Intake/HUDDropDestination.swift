import Foundation

/// Where a drop in the HUD goes (spec 09, regola "Sessione davanti"): the Sessione in front of the user when it is
/// open, which takes the Allegati for its next turn; otherwise a new Domanda.
///
/// The Sessione in front is the one under the pointer at the drop: its row in the Colonna, the Striscia or the Board,
/// or the one chosen in the Orbita.
nonisolated enum HUDDropDestination: Equatable, Sendable {
    /// The open Sessione with this id.
    case session(UUID)
    /// A new Domanda, under the Orb.
    case question

    /// Creates the destination of a drop over `session`; `nil` when no Sessione is in front.
    init(sessionInFront session: Session?) {
        if let session, session.isLive {
            self = .session(session.id)
        } else {
            self = .question
        }
    }

    /// The Allegati of the dropped `urls`: files and folders by path, web addresses as text.
    static func attachments(from urls: [URL]) -> [Allegato] {
        urls.map { url in url.isFileURL ? Allegato(fileAt: url) : Allegato(address: url) }
    }
}
