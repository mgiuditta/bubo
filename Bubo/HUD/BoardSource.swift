/// Where the Board's cards come from, to filter them: written by hand, or from the source of an issue (spec 16).
nonisolated enum BoardSource: Hashable, Sendable {
    /// Bozze written by hand, and Sessioni started without an issue.
    case manual
    /// Bozze and Sessioni from an issue of `source`.
    case issue(IssueLink.Source)

    /// Every source, in the order of the Board's filter.
    static var allCases: [BoardSource] {
        [.manual] + IssueLink.Source.allCases.map(BoardSource.issue)
    }

    /// Whether a card from `issue`, or written by hand when `nil`, comes from this source.
    func contains(_ issue: IssueLink?) -> Bool {
        switch self {
        case .manual: issue == nil
        case let .issue(source): issue?.source == source
        }
    }
}
