import Foundation

/// The issue a Sessione or a Bozza comes from: the key against doppioni, with its Progetto (spec 16).
nonisolated struct IssueLink: Codable, Hashable, Sendable {
    /// Where an issue lives.
    enum Source: String, Codable, CaseIterable, Sendable {
        case github
        case linear

        /// The name of the source, on the cards and in the Board's filter.
        var title: String {
            switch self {
            case .github: "GitHub"
            case .linear: "Linear"
            }
        }
    }

    /// What an issue already has on a Progetto: nothing, a Bozza, a Sessione still open, or one Archiviata or Fusa.
    enum Match: Equatable {
        case none
        /// A Bozza waiting in Da iniziare: ⌘I and `bubo://` open it.
        case draft(Draft)
        /// A Sessione that is not Archiviata: ⌘I opens it.
        case open(Session)
        /// The latest Sessione, Archiviata or Fusa: ⌘I asks whether to resume it or start a new one.
        case closed(Session)
    }

    var source: Source
    /// The issue's id in its source: the number on GitHub, the identifier such as `ENG-123` on Linear.
    var id: String

    /// The issue `number` on GitHub.
    static func github(_ number: Int) -> IssueLink {
        IssueLink(source: .github, id: String(number))
    }

    /// The Linear issue with `identifier`, such as `ENG-123`.
    static func linear(_ identifier: String) -> IssueLink {
        IssueLink(source: .linear, id: identifier)
    }

    /// The issue's number on GitHub; `nil` for another source or an id that is not a number.
    var number: Int? {
        switch source {
        case .github: Int(id)
        case .linear: nil
        }
    }

    /// The reference on the card and in the Sessione, such as `#42` or `ENG-123`.
    var label: String {
        switch source {
        case .github: "#\(id)"
        case .linear: id
        }
    }

    /// The branch of a Sessione on issue `number` titled `title`: `bubo/42-<slug>`, the slug as in
    /// ``Session/proposedBranch(for:)``. A taken name gets `-2`, `-3`… when the worktree is prepared.
    static func branch(forIssue number: Int, titled title: String) -> String {
        Session.proposedBranch(for: "\(number) \(title)")
    }

    /// The branch of a Sessione on the Linear issue `identifier`, from the `branchName` Linear suggests:
    /// `bubo/eng-123-fix-login` from `matteo/eng-123-fix-login`. The user's prefix goes, the identifier stays, since
    /// Linear links the PR by it; when the name lacks it, it comes first.
    static func branch(forLinear branchName: String, identifier: String) -> String {
        let name = branchName.split(separator: "/").last.map(String.init) ?? ""
        let branch = Session.proposedBranch(for: name)
        let words = branch.dropFirst("bubo/".count).split(separator: "-")
        let key = identifier.lowercased().split(separator: "-")
        let hasIdentifier = words.count >= key.count
            && (0...(words.count - key.count)).contains { Array(words[$0..<($0 + key.count)]) == key }
        return hasIdentifier ? branch : Session.proposedBranch(for: "\(identifier) \(name)")
    }

    /// What this issue already has on `project` among `drafts` and `sessions`: a Bozza first, then an open Sessione,
    /// else the latest closed one.
    func match(in sessions: [Session], drafts: [Draft] = [], on project: URL) -> Match {
        let path = project.standardizedFileURL.path
        if let draft = drafts.first(where: { $0.issue == self && $0.project.standardizedFileURL.path == path }) {
            return .draft(draft)
        }
        let linked = sessions.filter { $0.issue == self && $0.project.standardizedFileURL.path == path }
        if let open = linked.last(where: { $0.phase == .aperta }) { return .open(open) }
        return linked.last.map(Match.closed) ?? .none
    }
}
