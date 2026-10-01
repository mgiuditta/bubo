import Foundation

/// How `claude` approves the calls of a Sessione's turn, as its `permissionMode`.
nonisolated enum PermissionMode: String, Sendable {
    /// Every call nothing allows yet becomes a Richiesta di permesso.
    case manual = "default"
    /// The Modalità autonoma: `claude`'s classifier approves up to level 3; levels 4–5 still ask, through Bubo's gate.
    case autonomous = "auto"
}
