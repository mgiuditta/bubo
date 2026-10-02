import Foundation

/// A pull request as `gh pr view --json state,mergedAt,statusCheckRollup,url` describes it (spec 16).
nonisolated struct GitHubPullRequest: Decodable, Equatable, Sendable {
    /// Where the pull request is on GitHub.
    enum State: String, Decodable, Sendable {
        case open = "OPEN", closed = "CLOSED", merged = "MERGED"
    }

    var state: State
    /// When it was merged; `nil` while it is not.
    var mergedAt: Date?
    /// Its checks, as the status check rollup lists them.
    var checks: [PullRequestCheck]

    /// The fields Bubo asks `gh` for.
    static let fields = "state,mergedAt,statusCheckRollup,url"

    private enum CodingKeys: String, CodingKey {
        case state, mergedAt, statusCheckRollup
    }

    init(state: State, mergedAt: Date? = nil, checks: [PullRequestCheck] = []) {
        self.state = state
        self.mergedAt = mergedAt
        self.checks = checks
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(State.self, forKey: .state)
        mergedAt = state == .merged ? try container.decodeIfPresent(Date.self, forKey: .mergedAt) : nil
        checks = try container.decodeIfPresent([PullRequestCheck].self, forKey: .statusCheckRollup) ?? []
    }
}
