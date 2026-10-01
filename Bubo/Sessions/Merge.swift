import Foundation

/// A merge that Fondi made in a Progetto's checkout, with what undoing it needs.
nonisolated struct Merge: Equatable, Sendable {
    /// The repo's top folder.
    var checkout: URL
    /// The full name of the branch that moved, such as `refs/heads/main`.
    var branch: String
    /// The commit the branch was on before.
    var previous: String
    /// The commit Fondi made.
    var commit: String
}

/// Why Fondi, or undoing it, cannot go ahead.
nonisolated enum MergeError: LocalizedError, Equatable {
    /// The merge would conflict in these files.
    case conflicts([String])
    /// The checkout has unsaved changes in these files, which the merge would change.
    case dirtyCheckout([String])
    /// The checkout is not on a branch.
    case detachedHead
    /// The checkout's branch already has the Sessione's work.
    case nothingToMerge
    /// The checkout's branch moved on after the merge, which can no longer be undone.
    case moved
    /// The Sessione has blocchi that are not accepted, also new ones written since the revisione.
    case notAllAccepted

    var errorDescription: String? {
        switch self {
        case let .conflicts(files):
            String(localized: "Fondere ora darebbe conflitti in \(files.formatted()). Chiedi all'agente di risolverli nella Sessione.")
        case let .dirtyCheckout(files):
            String(localized: "Nel checkout del Progetto ci sono modifiche non salvate in \(files.formatted()), e il merge le cambierebbe. Fai un commit o mettile da parte, poi fondi.")
        case .detachedHead:
            String(localized: "Il checkout del Progetto non è su un branch. Passa a un branch, poi fondi.")
        case .nothingToMerge:
            String(localized: "Il branch del checkout ha già tutte le modifiche della Sessione.")
        case .moved:
            String(localized: "Non posso annullare il merge: nel frattempo il branch del checkout è cambiato.")
        case .notAllAccepted:
            String(localized: "Ci sono blocchi non ancora accettati. Rivedili, poi fondi.")
        }
    }
}
