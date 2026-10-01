import Foundation

/// What the user decided on a blocco in the revisione.
nonisolated enum HunkDecision: Codable, Equatable, Sendable {
    case accepted
    /// Rejected, with what the agent should do instead.
    case rejected(note: String?)
}
