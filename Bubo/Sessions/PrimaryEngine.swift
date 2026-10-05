import Foundation

/// The Motore principale (ADR 0014): the Motore Domande and Sessioni start on when no preference for the Tipo or the
/// Progetto chose one, and whether the other Motore is the Riserva. Set in Impostazioni › Modelli; Claude without a
/// Riserva until the user chooses otherwise, so that nothing changes for who used Bubo before.
nonisolated struct PrimaryEngine: Equatable, Sendable {
    /// The Motore Domande and Sessioni start on.
    var engine: Session.Engine = .claude
    /// Whether the other Motore answers when `engine` runs out of Quota or hits a limit.
    var hasReserve = false

    /// The defaults key of `engine`.
    static let engineKey = "engines.primary"
    /// The defaults key of `hasReserve`.
    static let reserveKey = "engines.primaryHasReserve"

    /// The Motore principale saved in `defaults`, or Claude without a Riserva where none is.
    static func saved(in defaults: UserDefaults) -> Self {
        var primary = Self()
        if let engine = defaults.string(forKey: engineKey).flatMap(Session.Engine.init(rawValue:)) {
            primary.engine = engine
        }
        primary.hasReserve = defaults.bool(forKey: reserveKey)
        return primary
    }
}
