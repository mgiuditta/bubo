import Foundation

/// A Bozza: a job to start on a Progetto, whose title and text become the prompt of its Sessione at Avvia. A Bozza from
/// an issue has only its title: the issue is read at Avvia.
nonisolated struct Draft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The Progetto's folder.
    var project: URL
    var title: String
    /// What to do, besides the title; may be empty.
    var text: String
    var createdAt: Date
    /// The issue the Bozza comes from, with ⌥↩ in ⌘I or a `bubo://` link; `nil` for one written by hand.
    var issue: IssueLink?

    /// Creates a Bozza on `project`, written now, from `issue` if any.
    init(title: String, text: String, project: URL, issue: IssueLink? = nil, createdAt: Date = .now) {
        id = UUID()
        self.title = title
        self.text = text
        self.project = project
        self.issue = issue
        self.createdAt = createdAt
    }

    /// The first prompt of the Sessione: the title, then the text if any.
    var prompt: String {
        text.isEmpty ? title : "\(title)\n\n\(text)"
    }

    /// Why the Bozza cannot start now: its Progetto is not reachable; `nil` when it can.
    var unreachableReason: String? {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: project.path, isDirectory: &isFolder), isFolder.boolValue { return nil }
        return String(localized: "Il Progetto non è più in \(project.path). Riporta lì la cartella o elimina la Bozza.")
    }
}
