import Foundation

/// What is chosen in the sidebar of the window, and so shown on the right (ADR 0013).
enum SidebarSelection: Hashable {
    /// The home: the big Orb and «Chiedi al tuo cervello».
    case brain
    case neurons
    case meetings
    /// A Domanda, a Sessione or a conversation of the command line, by ``ConversationItem/id``.
    case conversation(String)
    /// The Sessioni of a Progetto.
    case project(URL)
    /// The Board: Bozze, open Sessioni, those in review.
    case work

    /// The selection of the Sessione `id`.
    static func session(_ id: UUID) -> Self { .conversation("s-\(id)") }

    /// The selection of the Domanda `id`.
    static func question(_ id: UUID) -> Self { .conversation("q-\(id)") }
}
