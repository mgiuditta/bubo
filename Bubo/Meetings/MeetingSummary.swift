import Foundation

/// What a Riunione was about, what it decided and who does what next: written by the summary engine.
///
/// The section titles are part of the note's format, fixed in Italian as its properties.
nonisolated struct MeetingSummary: Equatable, Sendable {
    /// The points of the conversation.
    var summary: [String] = []
    /// The decisions taken.
    var decisions: [String] = []
    /// The actions, with who does them when the conversation says it.
    var actions: [String] = []

    /// What the model is asked, in the language of the note.
    static let instructions = """
        Riassumi in italiano questa Riunione, trascritta in automatico: «Io» è chi l'ha registrata, «Altri» sono gli \
        altri partecipanti. \(format)
        """

    /// What the model is asked to join the summaries of the pieces of a long Riunione.
    static let joiningInstructions = """
        Questi sono i riassunti, in ordine, delle parti di una stessa Riunione: «Io» è chi l'ha registrata, «Altri» \
        sono gli altri partecipanti. Uniscili in un solo riassunto in italiano, senza perdere le decisioni e le \
        azioni di nessuna parte, anche dell'ultima. \(format)
        """

    /// The answer's shape, the same for a whole Riunione and for its pieces.
    private static let format = """
        Rispondi solo con tre sezioni Markdown, in quest'ordine: "## Riassunto", "## Decisioni", "## Azioni", \
        ognuna con al più 6 punti elenco brevi. Nelle azioni scrivi chi fa cosa, quando si capisce. Niente \
        introduzione né conclusione. Non riportare chiavi, token, password né altri segreti.
        """

    /// `text` cut into pieces of at most `limit` characters, between lines when it can, in order.
    static func pieces(of text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var piece = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = line
            if !piece.isEmpty, piece.count + 1 + line.count > limit {
                pieces.append(piece)
                piece = ""
            }
            // A line longer than a piece is cut where the limit falls.
            while line.count > limit {
                pieces.append(String(line.prefix(limit)))
                line = line.dropFirst(limit)
            }
            piece += (piece.isEmpty ? "" : "\n") + line
        }
        if !piece.isEmpty { pieces.append(piece) }
        return pieces
    }

    /// Creates a summary of these items.
    init(summary: [String] = [], decisions: [String] = [], actions: [String] = []) {
        self.summary = summary
        self.decisions = decisions
        self.actions = actions
    }

    /// Creates the summary a model wrote as `## Riassunto`, `## Decisioni` and `## Azioni` with their items.
    ///
    /// Lines before the first known section, and other headings, are left out.
    init(markdown: String) {
        var section: WritableKeyPath<MeetingSummary, [String]>?
        for line in markdown.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                section = switch title {
                case "riassunto": \.summary
                case "decisioni": \.decisions
                case "azioni": \.actions
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
    var isEmpty: Bool { summary.isEmpty && decisions.isEmpty && actions.isEmpty }

    /// The summary with every secret `filter` finds replaced.
    func redacted(by filter: SecretFilter) -> MeetingSummary {
        MeetingSummary(summary: summary.map(filter.redacting), decisions: decisions.map(filter.redacting),
                       actions: actions.map(filter.redacting))
    }

    /// The note's sections: `## Riassunto`, `## Decisioni` and `## Azioni`, each with its items or "Niente.".
    var markdown: String {
        [("Riassunto", summary), ("Decisioni", decisions), ("Azioni", actions)].map { title, items in
            "## \(title)\n\n" + (items.isEmpty ? "Niente." : items.map { "- \($0)" }.joined(separator: "\n"))
        }
        .joined(separator: "\n\n")
    }
}
