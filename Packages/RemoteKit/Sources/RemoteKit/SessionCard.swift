import Foundation

/// What the iPhone shows of a Sessione: title, Progetto, Attività, Fase, the latest message and the diff (spec 21).
///
/// Travels only inside the encrypted payload of a ``RemoteRecord`` of kind `sessionCard`.
public struct SessionCard: Codable, Sendable, Equatable, Identifiable {
    /// What the Sessione is doing now.
    public enum Activity: String, Codable, Sendable, CaseIterable {
        case attende, errore, lavora, ferma
    }

    /// Where the Sessione is in its life.
    public enum Phase: String, Codable, Sendable, CaseIterable {
        case aperta, inRevisione, fusa, archiviata
    }

    /// How much the Sessione changed since its branch started.
    public struct DiffStats: Codable, Sendable, Equatable {
        /// The files changed.
        public var files: Int
        /// The lines added.
        public var addedLines: Int
        /// The lines removed.
        public var removedLines: Int

        /// Creates the statistics of a diff.
        public init(files: Int, addedLines: Int, removedLines: Int) {
            self.files = files
            self.addedLines = addedLines
            self.removedLines = removedLines
        }
    }

    /// The Sessione's identifier on the Mac.
    public let id: UUID
    /// The Sessione's title.
    public var title: String
    /// The Progetto's name: its folder's name, never its path.
    public var project: String
    /// What the Sessione is doing now.
    public var activity: Activity
    /// Where the Sessione is in its life.
    public var phase: Phase
    /// The latest thing the Sessione said or did, in one line; `nil` before its first.
    public var excerpt: String?
    /// The diff of the Sessione; `nil` while it has no copy, or git could not say.
    public var diff: DiffStats?

    /// Creates the card of a Sessione.
    public init(
        id: UUID,
        title: String,
        project: String,
        activity: Activity,
        phase: Phase,
        excerpt: String? = nil,
        diff: DiffStats? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.activity = activity
        self.phase = phase
        self.excerpt = excerpt
        self.diff = diff
    }
}

extension SessionCard {
    /// `cards` grouped by Progetto, the Progetti by name; in each, Attende te first, then Errore, Lavora and Ferma,
    /// then by title.
    public static func groupedByProject(_ cards: [SessionCard]) -> [(project: String, cards: [SessionCard])] {
        let order = Dictionary(uniqueKeysWithValues: Activity.allCases.enumerated().map { ($1, $0) })
        return Dictionary(grouping: cards, by: \.project)
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { project, cards in
                (project, cards.sorted {
                    (order[$0.activity] ?? 0, $0.title) < (order[$1.activity] ?? 0, $1.title)
                })
            }
    }
}
