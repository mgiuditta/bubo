import Foundation

/// The properties of a Riassunto di Sessione note, read by Obsidian: dates `AAAA-MM-GG`, links in quotes.
nonisolated struct SummaryProperties: Equatable, Sendable {
    /// The Sessione's title.
    var title: String
    /// The Progetto's name.
    var project: String
    /// The Sessione's branch; `nil` outside git or on the checkout.
    var branch: String?
    /// The Sessione's Fase when summarized.
    var phase: Session.Phase
    /// The Sessione, linked as `bubo://sessione/<id>`.
    var session: UUID
    /// The names of the related notes of the Secondo cervello, linked as `"[[nome]]"`.
    var related: [String] = []

    /// The frontmatter, between its `---` lines.
    func frontmatter(createdOn created: String, updatedOn updated: String) -> String {
        var lines = ["---", "titolo: \(Self.quoted(title))", "progetto: \(Self.quoted(project))"]
        if let branch { lines.append("branch: \(Self.quoted(branch))") }
        lines += [
            "fase: \(phase.rawValue)",
            "creata: \(created)",
            "aggiornata: \(updated)",
            "sessione: \(Self.quoted("bubo://sessione/\(session.uuidString.lowercased())"))",
            "correlate: [\(related.map { Self.quoted("[[\($0)]]") }.joined(separator: ", "))]",
            "---",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// `text` as a YAML string in double quotes, on one line.
    static func quoted(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return "\"" + line.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}
