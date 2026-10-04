import Foundation

/// The search by words straight in the notes of the Secondo cervello, as `grep` does: what `cerca` answers when the
/// Indice is not available.
///
/// It reads the same notes as the Indice, so excluded folders stay out here too.
nonisolated enum WordSearch {
    /// Notes beyond which the answer stops: the most relevant come first.
    static let maximumNotes = 8
    /// Lines of each note shown in the answer.
    static let maximumLines = 6

    /// Returns the answer to `cerca` for `text`: the notes under `folder`, outside `excludedFolders`, that contain
    /// every word of `text`, ignoring case and accents, each with its matching lines and its citation.
    static func toolResult(for text: String, in folder: String, excluding excludedFolders: Set<String> = []) -> String {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { folded(String($0)) }
        guard !words.isEmpty else { return SearchIndex.noResults }
        let matches = SecondBrainNotes.files(at: folder, in: folder, excluding: excludedFolders).notes.keys
            .compactMap { path -> (path: String, count: Int, lines: [String])? in
                guard let note = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let content = folded(note)
                guard words.allSatisfy(content.contains) else { return nil }
                let lines = note.split(whereSeparator: \.isNewline)
                    .filter { line in words.contains { folded(String(line)).contains($0) } }
                return (path, lines.count, lines.prefix(maximumLines).map(String.init))
            }
            .sorted { ($0.count, $1.path) > ($1.count, $0.path) }
            .prefix(maximumNotes)
        guard !matches.isEmpty else { return SearchIndex.noResults }
        let found = matches.map { match in
            let citation = NoteCitation(path: match.path, inFolder: folder).map { " (Cita come \($0.wikilink))" } ?? ""
            return "### \(match.path)\(citation)\n\n" + match.lines.joined(separator: "\n")
        }
        return "L'Indice non è disponibile: risultati della ricerca per parole nelle note.\n\n"
            + found.joined(separator: "\n\n---\n\n") + "\n\n---\n\n" + SearchIndex.citationRule
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
