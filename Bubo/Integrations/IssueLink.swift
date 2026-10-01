import Foundation

/// The issue a Sessione was started from: the key against doppioni, with its Progetto (spec 16).
nonisolated struct IssueLink: Codable, Hashable, Sendable {
    /// Where an issue lives.
    enum Source: String, Codable, Sendable {
        case github
    }

    /// What an issue already has on a Progetto: nothing, a Sessione still open, or one Archiviata or Fusa.
    enum Match: Equatable {
        case none
        /// A Sessione that is not Archiviata: ⌘I opens it.
        case open(Session)
        /// The latest Sessione, Archiviata or Fusa: ⌘I asks whether to resume it or start a new one.
        case closed(Session)
    }

    var source: Source
    /// The issue's id in its source: the number on GitHub.
    var id: String

    /// The issue `number` on GitHub.
    static func github(_ number: Int) -> IssueLink {
        IssueLink(source: .github, id: String(number))
    }

    /// The reference on the card and in the Sessione, such as `#42`.
    var label: String {
        switch source {
        case .github: "#\(id)"
        }
    }

    /// The branch of a Sessione on issue `number` titled `title`: `bubo/42-<slug>`, the slug as in
    /// ``Session/proposedBranch(for:)``. A taken name gets `-2`, `-3`… when the worktree is prepared.
    static func branch(forIssue number: Int, titled title: String) -> String {
        Session.proposedBranch(for: "\(number) \(title)")
    }

    /// What this issue already has on `project` among `sessions`: an open Sessione first, else the latest closed one.
    func match(in sessions: [Session], on project: URL) -> Match {
        let path = project.standardizedFileURL.path
        let linked = sessions.filter { $0.issue == self && $0.project.standardizedFileURL.path == path }
        if let open = linked.last(where: { $0.phase == .aperta }) { return .open(open) }
        return linked.last.map(Match.closed) ?? .none
    }
}
