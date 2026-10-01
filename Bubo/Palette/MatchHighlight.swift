import Foundation

/// Finds the words of a search in a fragment, the way the Indice matches them: whole words starting with a searched one,
/// regardless of case and accents.
nonisolated enum MatchHighlight {
    /// The ranges of the words of `text` that start with one of `words`, in order.
    static func ranges(in text: String, matching words: [String]) -> [Range<String.Index>] {
        let searched = words.map(fold).filter { !$0.isEmpty }
        guard !searched.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices + [text.endIndex] {
            let isWordCharacter = index < text.endIndex && (text[index].isLetter || text[index].isNumber)
            if isWordCharacter {
                if start == nil { start = index }
            } else if let wordStart = start {
                let word = fold(String(text[wordStart..<index]))
                if searched.contains(where: word.hasPrefix) { ranges.append(wordStart..<index) }
                start = nil
            }
        }
        return ranges
    }

    /// The words of `query` the Indice searches for.
    static func words(of query: String) -> [String] {
        query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Up to `length` characters of `text` on one line, starting a little before its first match, with `…` where cut.
    static func excerpt(of text: String, matching words: [String], length: Int = 220) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        let lead = 40
        var start = line.startIndex
        if let first = ranges(in: line, matching: words).first,
           line.distance(from: line.startIndex, to: first.lowerBound) > lead {
            start = line.index(first.lowerBound, offsetBy: -lead)
            // At the start of a word, never in the middle of one.
            while start < first.lowerBound, line[start].isLetter || line[start].isNumber { start = line.index(after: start) }
        }
        let end = line.index(start, offsetBy: length, limitedBy: line.endIndex) ?? line.endIndex
        return (start > line.startIndex ? "…" : "") + line[start..<end].trimmingCharacters(in: .whitespaces)
            + (end < line.endIndex ? "…" : "")
    }

    /// `text` without case and accents, as the Indice compares words.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
