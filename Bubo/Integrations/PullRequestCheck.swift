import Foundation

/// A check of a pull request: a check run, such as a GitHub Actions job, or a commit status, such as Vercel's.
nonisolated struct PullRequestCheck: Decodable, Equatable, Sendable {
    /// How the check ended, or that it did not yet.
    enum Outcome: Sendable {
        case passed, failed, pending, skipped
    }

    var name: String
    var outcome: Outcome
    /// Where the check shows its details; `nil` when GitHub gives none.
    var link: URL?
    /// What the check says of itself, for commit statuses.
    var details: String?

    init(name: String, outcome: Outcome, link: URL? = nil, details: String? = nil) {
        self.name = name
        self.outcome = outcome
        self.link = link
        self.details = details
    }

    /// The GitHub Actions job behind the check, whose failed log `gh run view --job` gives; `nil` for any other
    /// check, whose log stays on its own site.
    var jobID: Int? {
        guard let link else { return nil }
        let parts = link.pathComponents
        guard parts.count >= 4, parts[parts.count - 2] == "job", parts.contains("actions") else { return nil }
        return Int(parts[parts.count - 1])
    }

    private enum CodingKeys: String, CodingKey {
        case name, context, status, conclusion, state, detailsUrl, targetUrl, description
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = { (key: CodingKeys) in try container.decodeIfPresent(String.self, forKey: key) ?? "" }
        name = try text(.name).isEmpty ? try text(.context) : try text(.name)
        details = try text(.description).isEmpty ? nil : try text(.description)
        let link = try text(.detailsUrl).isEmpty ? try text(.targetUrl) : try text(.detailsUrl)
        self.link = URL(string: link)
        // A commit status has a state; a check run a status, then a conclusion once completed.
        let state = try text(.state)
        if !state.isEmpty {
            outcome = switch state {
            case "SUCCESS": .passed
            case "FAILURE", "ERROR": .failed
            default: .pending
            }
        } else if try text(.status) != "COMPLETED" {
            outcome = .pending
        } else {
            outcome = switch try text(.conclusion) {
            case "SUCCESS": .passed
            case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED": .failed
            default: .skipped
            }
        }
    }
}
