import Foundation

/// What Bubo last read of an open pull request: its checks, and whether the Sessione has work it does not have yet.
nonisolated struct PullRequestStatus: Equatable, Sendable {
    var checks: [PullRequestCheck]
    /// Whether the Sessione's copy has changes or commits not pushed to the pull request's branch.
    var isBehind: Bool

    /// The checks that failed, which Correggi sends to the agent.
    var failedChecks: [PullRequestCheck] { checks.filter { $0.outcome == .failed } }
}
