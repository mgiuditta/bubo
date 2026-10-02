import Foundation

/// A turn with nobody in front of it, the one an Esecuzione starts: no Richiesta di permesso ever waits.
///
/// Bubo's gate, the Progetto's rules, `rules` and the Modalità autonoma decide; anything else is denied, and lands in
/// the Sessione's report of denials.
nonisolated struct UnattendedTurn: Equatable, Sendable {
    /// The Regole dell'Automazione, passed as session rules of this turn only.
    var rules: [String] = []
    /// The `claude` alias that answers; `nil` for the user's own choice.
    var model: String?
}
