/// Picks the Sintesi parlata out of an answer as it streams (spec 08, `Voice/SpokenSummary`).
///
/// The model asked by voice writes it on the first line, after `marker`, so the voice starts with the first line and not
/// after the whole answer; that line is not shown, the rest of the answer is. Without the line, the first one or two
/// sentences of the prose, with no code and no tables.
nonisolated struct SpokenSummary {
    /// What opens the first line of an answer when it is the Sintesi parlata.
    static let marker = "Sintesi parlata:"
    /// What goes after a Domanda asked by voice: in the user's message, not in the system prompt, so the cache holds.
    static let instruction = """


        (Domanda fatta a voce. Comincia la risposta con una riga che inizia con "\(marker)" e contiene una o due frasi \
        da leggere ad alta voce, nella lingua della domanda, senza codice, tabelle, elenchi né Markdown; poi vai a capo \
        e scrivi la risposta completa.)
        """

    /// The Sintesi parlata, once it is known; it never changes after.
    private(set) var line: String?

    private enum Phase {
        /// The start of the answer could still be the marker.
        case deciding
        /// The first line is the marker's: it waits for the end of the line.
        case readingLine
        /// No marker: the answer is shown as it comes, and the summary is taken from its prose.
        case prose
    }

    private var phase = Phase.deciding
    /// The text not yet shown, while deciding or reading the line; all the answer in prose.
    private var text = ""

    /// Creates a reader before the first token.
    init() {}

    /// Reads `chunk` of the answer, and returns the part of it to show now.
    mutating func read(_ chunk: String) -> String {
        text += chunk
        switch phase {
        case .deciding:
            let start = text.drop { $0.isWhitespace }
            if start.hasPrefix(Self.marker) {
                phase = .readingLine
                return readLine()
            }
            // Still a possible start of the marker, or nothing but spaces yet: wait for the next chunk.
            if Self.marker.hasPrefix(start) { return "" }
            phase = .prose
            line = Self.firstSentences(of: text, isComplete: false)
            return text
        case .readingLine:
            return readLine()
        case .prose:
            if line == nil { line = Self.firstSentences(of: text, isComplete: false) }
            return chunk
        }
    }

    /// Ends the answer, and returns what is left to show; `line` is known from here, unless the answer said nothing.
    mutating func finish() -> String {
        switch phase {
        case .deciding, .prose:
            let shown = phase == .deciding ? text : ""
            if line == nil { line = Self.firstSentences(of: text, isComplete: true) }
            phase = .prose
            return shown
        case .readingLine:
            text += "\n"
            return readLine()
        }
    }

    /// Takes the summary off the first line once it ends, and returns the answer after it.
    private mutating func readLine() -> String {
        guard let end = text.firstIndex(of: "\n") else { return "" }
        let start = text.drop { $0.isWhitespace }.dropFirst(Self.marker.count)
        let summary = start[..<end].trimmingCharacters(in: .whitespaces)
        line = summary.isEmpty ? nil : summary
        let rest = String(text[text.index(after: end)...].drop { $0.isNewline })
        // An empty line falls back on the prose that follows it.
        phase = .prose
        text = rest
        if line == nil { line = Self.firstSentences(of: rest, isComplete: false) }
        return rest
    }

    /// The first two sentences of `answer`'s prose, without code blocks, tables, headings or list marks; `nil` until
    /// there are two whole sentences, or with `isComplete` whatever prose there is.
    static func firstSentences(of answer: String, isComplete: Bool) -> String? {
        var prose: [String] = []
        var isInCode = false
        for raw in answer.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                isInCode.toggle()
                continue
            }
            if isInCode || line.isEmpty || line.hasPrefix("|") || line.hasPrefix("#") { continue }
            let words = line.drop { ">-*+ ".contains($0) }
            prose.append(words.filter { !"`*_".contains($0) })
        }
        let text = prose.joined(separator: " ")
        var sentences: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex, sentences.count < 2 {
            let next = text.index(after: index)
            // A full stop is the end of a sentence only before a space: not in 3.5 nor in a file name.
            if ".!?…".contains(text[index]), next == text.endIndex ? isComplete : text[next].isWhitespace {
                sentences.append(text[start..<next])
                start = next
            }
            index = next
        }
        if sentences.count < 2, isComplete, start < text.endIndex { sentences.append(text[start...]) }
        guard sentences.count == 2 || isComplete && !sentences.isEmpty else { return nil }
        let summary = sentences.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return summary.isEmpty ? nil : summary
    }
}
