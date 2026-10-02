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
    /// The Consegna the Bozza comes from, with the chip `consegna`; `nil` for the others.
    var delivery: DraftDelivery?

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

/// Where a Bozza from a Consegna comes from, and what Avvia resumes (spec 24, Destinatario).
nonisolated struct DraftDelivery: Codable, Equatable, Sendable {
    /// The Consegna, from its manifest: the same Consegna opened again finds this Bozza.
    var id: UUID
    var person: String
    var machine: String
    /// The `sessionId` of the delivered conversation, which Avvia resumes.
    var sessionID: String
    /// The branch imported as `consegna/‹mittente›/‹nome›`; `nil` when the Consegna has none.
    var branch: String?
    /// The commit the branch starts after, which the revisione compares with.
    var baseCommit: String?
    /// Whether the sender's `claude` was newer than this Mac's: the Bozza says "Aggiorna claude prima di avviarla".
    var needsClaudeUpdate = false

    /// Whether the `installed` version of `claude` is older than the sender's, which wrote the transcript; unknown
    /// versions are not.
    static func needsClaudeUpdate(senderVersion: String?, installed: String?) -> Bool {
        guard let sender = senderVersion.flatMap(ClaudeVersion.init), let installed = installed.flatMap(ClaudeVersion.init)
        else { return false }
        return installed < sender
    }
}
