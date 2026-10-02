import Foundation

/// The column of the Board a Sessione sits in, derived from its Fase, its Attività and its PR, never dragged: the
/// Colonna groups the Sessioni the same way, so the two Viste never disagree.
nonisolated enum BoardColumn: String, CaseIterable, Identifiable, Sendable {
    case attendeTe, lavora, daGuardare, prAperta, fusa

    /// Where a Sessione's pull request is on GitHub.
    enum PullRequest: Sendable {
        case open, closed, merged
    }

    /// How long a merged Sessione stays in Fusa, even once it is Archiviata.
    static let mergedWindow = Duration.seconds(24 * 60 * 60)

    var id: Self { self }

    /// The column of a Sessione, by the first rule that holds; `nil` when it is off the Board.
    ///
    /// Archiviata is off, unless merged less than `mergedWindow` ago: then, like Fusa, in Fusa. Attende te or
    /// Errore → Attende te; Lavora → Lavora; a PR open → PR aperta; anything else → Da guardare.
    init?(phase: Session.Phase, activity: Session.Activity, pullRequest: PullRequest? = nil, mergedAt: Date?,
          now: Date) {
        if phase != .aperta && phase != .inRevisione {
            if let mergedAt {
                guard now.timeIntervalSince(mergedAt) < TimeInterval(Self.mergedWindow.components.seconds)
                else { return nil }
                self = .fusa
            } else if phase == .fusa {
                self = .fusa
            } else {
                return nil
            }
            return
        }
        switch activity {
        case .attende, .errore: self = .attendeTe
        case .lavora: self = .lavora
        case .ferma: self = pullRequest == .open ? .prAperta : .daGuardare
        }
    }

    /// The column of `session` at `now`; `nil` when it is off the Board.
    init?(_ session: Session, at now: Date) {
        // ponytail: In revisione means an open PR until the PR monitor reads its state (#153).
        self.init(phase: session.phase, activity: session.activity,
                  pullRequest: session.phase == .inRevisione ? .open : nil, mergedAt: session.mergedAt, now: now)
    }

    /// `sessions` in every column, in order, also the empty ones; off the Board the ones in no column. In Attende
    /// te the longest wait first; in the others the latest change first.
    static func columns(of sessions: [Session], at now: Date) -> [(column: BoardColumn, sessions: [Session])] {
        var members: [BoardColumn: [Session]] = [:]
        for session in sessions {
            guard let column = BoardColumn(session, at: now) else { continue }
            members[column, default: []].append(session)
        }
        return allCases.map { column in
            let sessions = members[column] ?? []
            return (column, column == .attendeTe
                ? sessions.sorted { $0.lastChange < $1.lastChange }
                : sessions.sorted { $0.lastChange > $1.lastChange })
        }
    }

    /// Whether its Sessioni show Fondi… and Archivia: only once the agent has finished, never while they wait for
    /// the user or failed, which stay in Attende te until the user acts.
    var hasNextStep: Bool {
        self == .daGuardare || self == .prAperta
    }

    /// The column's title on the Board and in the Colonna.
    var title: LocalizedStringResource {
        switch self {
        case .attendeTe: LocalizedStringResource("attivita.attendeTe", defaultValue: "Attende te")
        case .lavora: LocalizedStringResource("attivita.lavora", defaultValue: "Lavora")
        case .daGuardare: "Da guardare"
        case .prAperta: "PR aperta"
        case .fusa: LocalizedStringResource("fase.fusa", defaultValue: "Fusa")
        }
    }
}

private nonisolated extension Session {
    /// When the Sessione last changed Attività or was merged.
    var lastChange: Date {
        max(activitySince ?? .distantPast, mergedAt ?? .distantPast)
    }
}
