import Foundation

/// The title and the description Apri PR proposes, which the user edits; the line that closes the issue is Bubo's,
/// added by ``body(closing:)`` (spec 16).
nonisolated struct PullRequestText: Equatable, Sendable {
    var title: String
    var description: String

    /// The most characters of a title: GitHub shows about this many in its lists.
    static let titleLimit = 72

    /// Creates the text with `title` and `description`.
    init(title: String, description: String) {
        self.title = title
        self.description = description
    }

    /// The text a model answered: its first line the title, the rest the description; `nil` without a title.
    init?(answer: String) {
        let lines = answer.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let title = first.replacing(#/^(?:#+\s*|\*\*\s*|(?i:titolo|title)\s*:\s*)+/#, with: "")
            .replacing("**", with: "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        self.title = String(title.prefix(Self.titleLimit))
        description = lines.dropFirst().joined(separator: "\n")
            .replacing(#/^\s*(?i:descrizione|description)\s*:\s*/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text without a model: the Sessione's title, then its summary and the perché of its blocchi.
    init(title: String, summary: SessionSummary?, reasons: [String]) {
        self.title = String(title.prefix(Self.titleLimit))
        description = Self.material(summary: summary, reasons: reasons)
    }

    /// The line that closes `issue` when the pull request is merged into the default branch: `Closes #42` on
    /// GitHub, `Fixes ENG-123` on Linear.
    static func closingLine(for issue: IssueLink) -> String {
        switch issue.source {
        case .github: "Closes \(issue.label)"
        case .linear: "Fixes \(issue.label)"
        }
    }

    /// The body of the pull request: the description, then the line that closes `issue`, unless the description
    /// already has it.
    func body(closing issue: IssueLink?) -> String {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let issue else { return description }
        let line = Self.closingLine(for: issue)
        if description.localizedCaseInsensitiveContains(line) { return description }
        return description.isEmpty ? line : description + "\n\n" + line
    }

    /// What the model is asked.
    static let instructions = """
        Scrivi titolo e descrizione di una pull request su GitHub a partire dal riassunto di una Sessione di lavoro \
        e dai motivi delle modifiche. Rispondi in italiano: sulla prima riga solo il titolo, al massimo 72 caratteri, \
        all'imperativo; poi una riga vuota e la descrizione in Markdown, al massimo 120 parole, con punti elenco \
        brevi. Niente intestazioni, niente "Closes" o "Fixes": li aggiunge Bubo. Non riportare chiavi, token, \
        password né altri segreti.
        """

    /// What the model reads: the Sessione's title, its summary and the perché of its blocchi.
    static func prompt(title: String, summary: SessionSummary?, reasons: [String]) -> String {
        "Titolo della Sessione: \(title)\n\n" + material(summary: summary, reasons: reasons)
    }

    /// The summary, then the perché once each.
    private static func material(summary: SessionSummary?, reasons: [String]) -> String {
        var parts: [String] = []
        if let summary, !summary.isEmpty { parts.append(summary.markdown) }
        var seen = Set<String>()
        let unique = reasons.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if !unique.isEmpty {
            parts.append("## Perché\n\n" + unique.map { "- " + $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
                .joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }
}
