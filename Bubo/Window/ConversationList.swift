import Foundation

/// One entry of the Conversazioni in the sidebar: a Domanda, a Sessione or a conversation of the command line.
enum ConversationItem: Identifiable, Equatable {
    case question(ArchivedQuestion)
    case session(id: UUID, title: String, project: URL, date: Date, activity: Session.Activity?)
    case cli(id: String, title: String, project: URL?, date: Date)

    /// Unique across the three kinds: `q-`, `s-` or `c-` before the item's own id.
    var id: String {
        switch self {
        case .question(let question): "q-\(question.id)"
        case .session(let id, _, _, _, _): "s-\(id)"
        case .cli(let id, _, _, _): "c-\(id)"
        }
    }

    var title: String {
        switch self {
        case .question(let question): question.title
        case .session(_, let title, _, _, _), .cli(_, let title, _, _): title
        }
    }

    /// When it last moved, for the order and the day group.
    var date: Date {
        switch self {
        case .question(let question): question.date
        case .session(_, _, _, let date, _), .cli(_, _, _, let date): date
        }
    }
}

/// The day groups of the Conversazioni, in the order they show.
enum DayGroup: Int, Comparable {
    case today, yesterday, thisWeek, earlier

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The group's heading in the sidebar.
    var title: LocalizedStringResource {
        switch self {
        case .today: "Oggi"
        case .yesterday: "Ieri"
        case .thisWeek: "Questa settimana"
        case .earlier: "Prima"
        }
    }
}

/// The Domande and the Sessioni in one list, by day (ADR 0013).
enum ConversationList {
    /// The items of the sidebar, newest first; the command line's conversations only when `includingCLI`.
    static func items(questions: [ArchivedQuestion], sessions: [Session], cli: [CLIConversation],
                      includingCLI: Bool) -> [ConversationItem] {
        var items = questions.map(ConversationItem.question)
        items += sessions.map { session in
            .session(id: session.id, title: session.title, project: session.project,
                     date: session.activitySince ?? .distantPast, activity: session.isLive ? session.activity : nil)
        }
        if includingCLI {
            items += cli.map { .cli(id: $0.id, title: $0.title, project: $0.folder, date: $0.lastModified) }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// `items` in day groups as seen at `now`, newest first in each; empty groups are left out.
    static func groups(of items: [ConversationItem], now: Date,
                       calendar: Calendar) -> [(group: DayGroup, items: [ConversationItem])] {
        let grouped = Dictionary(grouping: items) { group(of: $0.date, now: now, calendar: calendar) }
        return grouped.keys.sorted().map { key in (key, grouped[key, default: []].sorted { $0.date > $1.date }) }
    }

    private static func group(of date: Date, now: Date, calendar: Calendar) -> DayGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= weekAgo {
            return .thisWeek
        }
        return .earlier
    }
}
