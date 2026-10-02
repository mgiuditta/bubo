import Foundation

/// What a Sessione did, what it decided and what it leaves open: the body of its Riassunto di Sessione.
///
/// The section titles are part of the note's format, fixed in Italian as its properties.
nonisolated struct SessionSummary: Equatable, Sendable {
    /// What was done.
    var done: [String]
    /// The decisions taken.
    var decisions: [String]
    /// What is left open.
    var open: [String]

    /// The most words a summary has (spec 13).
    static let wordLimit = 200

    /// Creates a summary of these items.
    init(done: [String] = [], decisions: [String] = [], open: [String] = []) {
        self.done = done
        self.decisions = decisions
        self.open = open
    }

    /// Creates the summary a model wrote as `## Fatto`, `## Decisioni` and `## Aperto` with their items.
    ///
    /// Lines before the first known section, and other headings, are left out.
    init(markdown: String) {
        self.init()
        var section: WritableKeyPath<SessionSummary, [String]>?
        for line in markdown.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                section = switch title {
                case "fatto": \.done
                case "decisioni": \.decisions
                case "aperto": \.open
                default: nil
                }
                continue
            }
            let item = line.replacing(#/^(?:[-*•]|\d+[.)])\s+/#, with: "").trimmingCharacters(in: .whitespaces)
            guard let section, !item.isEmpty else { continue }
            self[keyPath: section].append(item)
        }
    }

    /// Whether the summary has no item.
    var isEmpty: Bool { done.isEmpty && decisions.isEmpty && open.isEmpty }

    /// The words of the items.
    var wordCount: Int { (done + decisions + open).reduce(0) { $0 + Self.words(in: $1).count } }

    /// The summary within `limit` words: items go from the longest section, the last one first; a single item left
    /// over the limit loses its last words.
    func limited(toWords limit: Int = wordLimit) -> SessionSummary {
        var summary = self
        let sections: [WritableKeyPath<SessionSummary, [String]>] = [\.done, \.decisions, \.open]
        while summary.wordCount > limit {
            let longest = sections.max { summary[keyPath: $0].count < summary[keyPath: $1].count } ?? \.done
            if summary[keyPath: longest].count > 1 {
                summary[keyPath: longest].removeLast()
                continue
            }
            // One item per section at most: the longest item loses the words over the limit.
            let wordiest = sections.max {
                Self.words(in: summary[keyPath: $0].first ?? "").count < Self.words(in: summary[keyPath: $1].first ?? "").count
            } ?? \.done
            let words = Self.words(in: summary[keyPath: wordiest][0])
            let excess = summary.wordCount - limit
            summary[keyPath: wordiest][0] = words.dropLast(excess).joined(separator: " ")
            if words.count <= excess { summary[keyPath: wordiest].removeAll() }
        }
        return summary
    }

    /// The summary with every secret `filter` finds replaced.
    func redacted(by filter: SecretFilter) -> SessionSummary {
        SessionSummary(done: done.map(filter.redacting), decisions: decisions.map(filter.redacting),
                       open: open.map(filter.redacting))
    }

    /// The note's body: `## Fatto`, `## Decisioni` and `## Aperto`, each with its items on one line or "Niente.".
    var markdown: String {
        [("Fatto", done), ("Decisioni", decisions), ("Aperto", open)].map { title, items in
            let list = items.isEmpty ? "Niente." : items.map { item in
                "- " + item.split(whereSeparator: \.isNewline).joined(separator: " ")
            }
            .joined(separator: "\n")
            return "## \(title)\n\n\(list)\n"
        }
        .joined(separator: "\n")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
