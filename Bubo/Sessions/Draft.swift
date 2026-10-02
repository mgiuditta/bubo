import Foundation

/// A Bozza: a job to start on a Progetto, whose title and text become the prompt of its Sessione at Avvia. A Bozza from
/// a GitHub issue has only its title: the issue is read at Avvia. One from Linear keeps what Linear sent as its text.
nonisolated struct Draft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The Progetto's folder.
    var project: URL
    var title: String
    /// What to do, besides the title; may be empty.
    var text: String
    var createdAt: Date
    /// The issue the Bozza comes from, with ⌥↩ in ⌘I, a `bubo://` link or Linear; `nil` for one written by hand.
    var issue: IssueLink?
    /// The branch its Sessione starts on; `nil` for `bubo/<slug>` of its title.
    var branch: String?

    /// Creates a Bozza on `project`, written now, from `issue` if any, whose Sessione starts on `branch` if given.
    init(title: String, text: String, project: URL, issue: IssueLink? = nil, branch: String? = nil,
         createdAt: Date = .now) {
        id = UUID()
        self.title = title
        self.text = text
        self.project = project
        self.issue = issue
        self.branch = branch
        self.createdAt = createdAt
    }

    /// The first prompt of the Sessione: the title, then the text if any. From Linear, the text is written by
    /// others: it goes between markers, as material.
    var prompt: String {
        if let issue, issue.source == .linear {
            return LinearLink.prompt(forIssue: issue.id, titled: title, text: text)
        }
        return text.isEmpty ? title : "\(title)\n\n\(text)"
    }

    /// Why the Bozza cannot start now: its Progetto is not reachable; `nil` when it can.
    var unreachableReason: String? {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: project.path, isDirectory: &isFolder), isFolder.boolValue { return nil }
        return String(localized: "Il Progetto non è più in \(project.path). Riporta lì la cartella o elimina la Bozza.")
    }
}
