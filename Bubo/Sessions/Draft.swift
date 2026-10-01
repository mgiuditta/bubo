import Foundation

/// A Bozza: a job to start on a Progetto, whose title and text become the prompt of its Sessione at Avvia.
// ponytail: only Bozze written by hand; the source and the external id come with the Bozze from issues (#134).
nonisolated struct Draft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The Progetto's folder.
    var project: URL
    var title: String
    /// What to do, besides the title; may be empty.
    var text: String
    var createdAt: Date

    /// Creates a Bozza on `project`, written now.
    init(title: String, text: String, project: URL, createdAt: Date = .now) {
        id = UUID()
        self.title = title
        self.text = text
        self.project = project
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
