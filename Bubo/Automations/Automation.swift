import Foundation

/// A request that runs on a Progetto with nobody in front of it: today by [Avvia ora], each time in a new Sessione
/// (spec 19).
nonisolated struct Automation: Codable, Identifiable, Equatable, Sendable {
    /// Which model answers an Esecuzione.
    enum ModelChoice: Codable, Equatable, Hashable, Sendable {
        /// No model passed, as in the Sessioni: the user's own choice in `claude` until the router reaches them.
        case router
        /// A `claude` alias, such as `sonnet`.
        case fixed(alias: String)

        /// The alias passed to `claude`; `nil` for the router.
        var alias: String? {
            if case let .fixed(alias) = self { alias } else { nil }
        }
    }

    let id: UUID
    var name: String
    /// The Progetto's folder.
    var project: URL
    /// What the agent is asked at each Esecuzione.
    var request: String
    var model = ModelChoice.router
    /// Whether the Esecuzioni run in the Modalità autonoma; on by default, it counts only where the Sessione has a
    /// worktree of its own, never outside git.
    var isAutonomous = true
    /// The Regole di permesso "in questa Automazione", as `permissions.allow` writes them: `Bash(npm test)`. They
    /// apply only to its Esecuzioni and never reach the settings of `claude`.
    var rules: [String] = []
    /// The latest Esecuzione; `nil` until the first one.
    var lastExecution: Execution?
}

/// One run of an Automazione, in a Sessione of its own.
nonisolated struct Execution: Codable, Equatable, Sendable {
    /// How the Esecuzione went.
    // ponytail: the other outcomes come with the schedule (#169).
    enum Outcome: String, Codable, Sendable {
        case inCorso, fatta, errore
    }

    var startedAt: Date
    /// The Sessione the Esecuzione runs in.
    var session: UUID
    var outcome: Outcome
    /// How many actions were denied in its turn.
    var denialCount: Int
}

/// The mark of a Sessione started by an Automazione: "Automazione · nome · ora".
nonisolated struct AutomationMark: Codable, Equatable, Sendable {
    let automation: UUID
    let name: String
    let startedAt: Date
}
