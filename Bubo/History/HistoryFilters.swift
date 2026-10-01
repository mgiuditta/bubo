import Foundation

/// The filters of the Cronologia window's left column: Progetto, date and fonte; by default every conversation.
nonisolated struct HistoryFilters: Equatable, Sendable {
    /// The ages the date filter offers, in days; `nil` is always.
    static let dayOptions: [Int?] = [7, 30, 90, nil]

    /// Only the conversations of the Progetto with this name; `nil` for every Progetto.
    var project: String?
    /// Only the conversations of the last this many days; `nil` for always.
    var days: Int?
    /// Only the conversations from there; `nil` for both.
    var source: ConversationSource?

    /// The name the filter column gives the Progetto of `result`: its folder's name; `nil` if unknown.
    static func projectName(of result: ConversationResult) -> String? {
        result.project?.lastPathComponent
    }

    /// Whether `result` passes every filter at `now`.
    func admits(_ result: ConversationResult, at now: Date) -> Bool {
        (project == nil || Self.projectName(of: result) == project)
            && (days.map { result.date >= now.addingTimeInterval(-Double($0) * 86_400) } ?? true)
            && (source == nil || result.source == source)
    }

    /// How many of `results` pass the filters at `now`.
    func count(in results: [ConversationResult], at now: Date) -> Int {
        results.count { admits($0, at: now) }
    }

    /// The filters with one of them changed by `change`, for the count next to each choice.
    func changing(_ change: (inout HistoryFilters) -> Void) -> HistoryFilters {
        var changed = self
        change(&changed)
        return changed
    }
}
