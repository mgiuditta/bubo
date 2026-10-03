import Foundation

/// A piece of an answer as the conversation shows it: prose with inline Markdown, or a block of code between ``` fences.
nonisolated enum AnswerBlock: Equatable, Sendable {
    /// Text with inline Markdown, headings and `[[nota]]` wikilinks, as written.
    case prose(String)
    /// The code between the fences, without them.
    case code(String)

    /// The blocks of `answer` in order, empty prose left out.
    ///
    /// A fence still open, as while the answer streams, runs to the end of the answer.
    static func blocks(of answer: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var lines: [Substring] = []
        var isInCode = false
        func close() {
            let text = lines.joined(separator: "\n")
            if isInCode {
                blocks.append(.code(text))
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.prose(text.trimmingCharacters(in: .newlines)))
            }
            lines = []
        }
        for line in answer.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // An opening fence may name a language; a closing one is the backticks alone.
            if isInCode ? trimmed == "```" : trimmed.hasPrefix("```") {
                close()
                isInCode.toggle()
            } else {
                lines.append(line)
            }
        }
        if isInCode || !lines.isEmpty { close() }
        return blocks
    }

    /// `prose` with its inline Markdown applied, its headings in bold and its wikilinks as links that carry their
    /// citation.
    ///
    /// Markdown cut short while it streams, an unclosed `**` for one, stays as written.
    ///
    /// The answer is the model's, which a file or a page can steer: of the links it writes only `http` and `https`
    /// stay links, and a note opens only from a wikilink.
    static func formatted(_ prose: String) -> AttributedString {
        let markdown = prose.split(separator: "\n", omittingEmptySubsequences: false)
            .map(boldingHeading)
            .joined(separator: "\n")
        // A scheme the model cannot know marks the wikilinks among the links.
        let scheme = "w" + UUID().uuidString.lowercased().filter(\.isHexDigit)
        let linked = NoteCitation.markdownLinking(markdown, scheme: scheme)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var formatted = try? AttributedString(markdown: linked.markdown, options: options) else {
            return NoteCitation.linking(prose)
        }
        for (link, range) in Array(formatted.runs[\.link]) {
            guard let link else { continue }
            if link.scheme == scheme {
                formatted[range].link = Int(link.absoluteString.dropFirst(scheme.count + 1))
                    .flatMap { linked.citations.indices.contains($0) ? linked.citations[$0].link : nil }
            } else if !["http", "https"].contains(link.scheme?.lowercased()) {
                formatted[range].link = nil
            }
        }
        return formatted
    }

    /// `line` written as bold when it is a heading, `## Titolo`; any other line as it is.
    private static func boldingHeading(_ line: Substring) -> String {
        let hashes = line.prefix { $0 == "#" }.count
        let title = line.dropFirst(hashes)
        guard (1...6).contains(hashes), title.first == " " else { return String(line) }
        let text = title.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? String(line) : "**\(text)**"
    }
}
