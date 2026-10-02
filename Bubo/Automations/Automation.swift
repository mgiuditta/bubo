import Foundation

/// A request that runs on a Progetto with nobody in front of it, by its Ripetizione or by [Avvia ora], each time in a
/// new Sessione (spec 19).
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
    /// When it runs by itself; `nil` for only by [Avvia ora], as the Automazioni made before the Ripetizioni.
    var recurrence: Recurrence?
    /// Whether it is in pausa: no Esecuzione starts by itself. [Avvia ora] still works.
    var isPaused = false
    /// Why Bubo put it in pausa by itself; `nil` when the user did, or it is not in pausa.
    var pauseReason: PauseReason?
    /// Its Esecuzioni, oldest first, also the Saltate: at most ``historyLimit``, the latest ones.
    var executions: [Execution] = []

    /// Why Bubo put an Automazione in pausa by itself.
    enum PauseReason: String, Codable, Sendable {
        /// Its Progetto's folder is gone: moved, or on a disk not attached.
        case projectMissing
    }

    /// The Esecuzioni an Automazione keeps: a week of one per hour, and some more.
    static let historyLimit = 200

    /// The latest Esecuzione; `nil` until the first one.
    var lastExecution: Execution? { executions.last }

    init(id: UUID, name: String, project: URL, request: String, model: ModelChoice = .router,
         isAutonomous: Bool = true, recurrence: Recurrence? = nil) {
        self.id = id
        self.name = name
        self.project = project
        self.request = request
        self.model = model
        self.isAutonomous = isAutonomous
        self.recurrence = recurrence
    }

    /// When its next Esecuzione starts by itself, after `date`; `nil` in pausa, without a Ripetizione, or once a
    /// single run is past.
    func nextDate(after date: Date, in calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard !isPaused else { return nil }
        return recurrence?.nextDate(after: date, in: calendar)
    }
}

nonisolated extension Automation {
    private enum LegacyKeys: String, CodingKey {
        case lastExecution
    }

    /// Decodes an Automazione, also one saved before its Ripetizione, its pausa and its history were kept: its only
    /// Esecuzione was then its latest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        project = try container.decode(URL.self, forKey: .project)
        request = try container.decode(String.self, forKey: .request)
        model = try container.decodeIfPresent(ModelChoice.self, forKey: .model) ?? .router
        isAutonomous = try container.decodeIfPresent(Bool.self, forKey: .isAutonomous) ?? true
        rules = try container.decodeIfPresent([String].self, forKey: .rules) ?? []
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        pauseReason = try container.decodeIfPresent(PauseReason.self, forKey: .pauseReason)
        if let executions = try container.decodeIfPresent([Execution].self, forKey: .executions) {
            self.executions = executions
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            executions = try legacy.decodeIfPresent(Execution.self, forKey: .lastExecution).map { [$0] } ?? []
        }
    }
}

/// One run of an Automazione, in a Sessione of its own.
nonisolated struct Execution: Codable, Equatable, Sendable {
    /// How the Esecuzione went.
    enum Outcome: String, Codable, Sendable {
        /// Its turn is still going.
        case inCorso
        /// It left changes, or a message, or denials: the user has something to look at.
        case fatta
        /// No changes, no denials, and "Niente da segnalare." as its last message: archived with no trace but here.
        case senzaModifiche
        /// It never started: ``Execution/skipReason`` says why.
        case saltata
        /// Bubo quit, or the Mac went to sleep, while it worked.
        case interrotta
        /// Its turn failed.
        case errore
    }

    /// How the Esecuzione went, in the Automazioni window.
    var title: String {
        switch outcome {
        case .inCorso: String(localized: "In corso")
        case .fatta: String(localized: "Fatta")
        case .senzaModifiche: String(localized: "Senza modifiche")
        case .saltata where skipReason == .sovrapposta: String(localized: "Saltata (sovrapposta)")
        case .saltata: String(localized: "Saltata")
        case .interrotta: String(localized: "Interrotta")
        case .errore: String(localized: "Errore")
        }
    }

    /// Why an Esecuzione did not start.
    enum SkipReason: String, Codable, Sendable {
        /// The same Automazione was still at work, or, outside git, another Sessione worked in the Progetto's folder.
        case sovrapposta
    }

    /// When it started, or for a Saltata when it should have.
    var startedAt: Date
    /// When its Ripetizione had it due; `nil` for [Avvia ora].
    var scheduledAt: Date?
    /// The Sessione the Esecuzione runs in; `nil` for a Saltata.
    var session: UUID?
    var outcome: Outcome
    /// Why it did not start; `nil` unless Saltata.
    var skipReason: SkipReason?
    /// How many actions were denied in its turn.
    var denialCount: Int = 0
}

/// The mark of a Sessione started by an Automazione: "Automazione · nome · ora".
nonisolated struct AutomationMark: Codable, Equatable, Sendable {
    let automation: UUID
    let name: String
    let startedAt: Date
}
