import Foundation

/// A `bubo://sessione/<id>` link, the one each Riassunto di Sessione note carries (spec 13).
///
/// Like any link, anyone can write one: it only ever shows a Sessione, never starts one. Anything but a Sessione's id
/// after `sessione/`, a query or a fragment make it no link at all.
nonisolated struct SessionLink: Equatable, Sendable {
    /// Where a link leads, among the Sessioni Bubo keeps.
    enum Destination: Equatable {
        /// A live Sessione, shown in the HUD.
        case hud(Session.ID)
        /// A Sessione Fusa or Archiviata, read in the Cronologia window on its latest conversation.
        case history(ConversationResult)
        /// No Sessione with that id, or one with no conversation to read.
        case unavailable
    }

    /// The id of the Sessione.
    var id: Session.ID

    /// The Sessione `url` asks for; `nil` when it is not a valid `bubo://sessione` link.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "bubo", url.host()?.lowercased() == "sessione",
              url.query() == nil, url.fragment() == nil
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1, let id = UUID(uuidString: components[0]) else { return nil }
        self.id = id
    }

    /// Where the link leads among `sessions`.
    func destination(among sessions: [Session]) -> Destination {
        guard let session = sessions.first(where: { $0.id == id }) else { return .unavailable }
        if session.isLive { return .hud(session.id) }
        return ConversationResult(latestOf: session).map(Destination.history) ?? .unavailable
    }
}
