import Foundation

/// The machine of the Attività: what `claude` reports moves a Sessione between Lavora, Attende te and Ferma;
/// Errore comes from a failed turn.
nonisolated extension Session {
    /// Moves the Sessione to `activity`; the wait starts again only when the Attività changes.
    mutating func enter(_ activity: Activity, at date: Date = .now) {
        guard activity != self.activity || activitySince == nil else { return }
        self.activity = activity
        activitySince = date
    }

    /// Updates the Attività or the summary from what `claude` reports at `date`.
    ///
    /// Only `idle` stops the Sessione: `claude` sends it after the result and after the subagents in the
    /// background end, so a Sessione never looks finished while they still work. It never hides an Errore.
    mutating func apply(_ progress: AgentProgress, at date: Date = .now) {
        switch progress {
        case .state(.running): enter(.lavora, at: date)
        case .state(.requiresAction): enter(.attende, at: date)
        case .state(.idle): if activity != .errore { enter(.ferma, at: date) }
        case let .summary(text): summary = text
        case let .edit(file, lines):
            guard let summary else { return }
            edits.append(EditNote(file: file, why: summary, lines: lines))
            if edits.count > Self.editNoteLimit { edits.removeFirst(edits.count - Self.editNoteLimit) }
        case .read, .ranCommand, .sandboxBlock, .variante: break
        case let .memory(event):
            memoryLines.append(MemoryLine(event: event, date: date))
            if memoryLines.count > Self.memoryLineLimit { memoryLines.removeFirst(memoryLines.count - Self.memoryLineLimit) }
        }
    }

    /// `sessions` grouped by Attività in the Colonna's order, without empty groups: in Attende te the longest
    /// wait first, in the others the order of `sessions`.
    static func grouped(_ sessions: [Session]) -> [(activity: Activity, sessions: [Session])] {
        Activity.allCases.compactMap { activity in
            var members = sessions.filter { $0.activity == activity }
            guard !members.isEmpty else { return nil }
            if activity == .attende {
                members.sort { ($0.activitySince ?? .distantPast) < ($1.activitySince ?? .distantPast) }
            }
            return (activity, members)
        }
    }

    /// `sessions` in the order of the Colonna's groups, in one list: Attende te first, the longest wait on top.
    static func inActivityOrder(_ sessions: [Session]) -> [Session] {
        grouped(sessions).flatMap(\.sessions)
    }
}
