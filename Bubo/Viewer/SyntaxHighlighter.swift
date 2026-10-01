import Foundation

/// A simple syntax highlighter for the visore: keywords, strings, numbers and comments, line by line (spec 15).
///
/// No grammar per language: one scanner with the comment marks of the file's extension and the keywords of the
/// common languages together. Enough to read code, not to understand it.
nonisolated enum SyntaxHighlighter {
    /// What a stretch of code is.
    enum Kind: Equatable, Sendable {
        case keyword, string, number, comment
    }

    /// A stretch of a line and what it is.
    struct Span: Equatable, Sendable {
        var kind: Kind
        var range: Range<String.Index>
    }

    /// The highlighted stretches of each of `lines`, in order and not overlapping; none for text such as Markdown.
    static func spans(of lines: [String], fileExtension: String) -> [[Span]] {
        guard let language = Language(fileExtension: fileExtension.lowercased()) else {
            return lines.map { _ in [] }
        }
        var isInBlockComment = false
        return lines.map { spans(of: $0, in: language, isInBlockComment: &isInBlockComment) }
    }

    /// The comment marks and quotes of a family of languages.
    private struct Language {
        var lineComment: String
        var hasBlockComments: Bool
        var quotes: Set<Character>

        init?(fileExtension: String) {
            switch fileExtension {
            case "md", "markdown", "txt", "text", "rst", "log", "csv", "tsv":
                return nil
            case "py", "rb", "sh", "bash", "zsh", "fish", "yml", "yaml", "toml", "r", "pl", "mk", "cmake", "conf":
                self.init(lineComment: "#", hasBlockComments: false, quotes: ["\"", "'", "`"])
            case "sql", "lua", "hs":
                self.init(lineComment: "--", hasBlockComments: true, quotes: ["\"", "'"])
            case "rs":
                // A `'` opens a lifetime more often than a character.
                self.init(lineComment: "//", hasBlockComments: true, quotes: ["\""])
            default:
                self.init(lineComment: "//", hasBlockComments: true, quotes: ["\"", "'", "`"])
            }
        }

        private init(lineComment: String, hasBlockComments: Bool, quotes: Set<Character>) {
            self.lineComment = lineComment
            self.hasBlockComments = hasBlockComments
            self.quotes = quotes
        }
    }

    private static func spans(of line: String, in language: Language, isInBlockComment: inout Bool) -> [Span] {
        var spans: [Span] = []
        var index = line.startIndex
        if isInBlockComment {
            guard let end = line.range(of: "*/") else {
                return line.isEmpty ? [] : [Span(kind: .comment, range: line.startIndex..<line.endIndex)]
            }
            spans.append(Span(kind: .comment, range: line.startIndex..<end.upperBound))
            index = end.upperBound
            isInBlockComment = false
        }
        while index < line.endIndex {
            let rest = line[index...]
            let character = line[index]
            if rest.hasPrefix(language.lineComment) {
                spans.append(Span(kind: .comment, range: index..<line.endIndex))
                break
            }
            if language.hasBlockComments, rest.hasPrefix("/*") {
                if let end = line[line.index(index, offsetBy: 2)...].range(of: "*/") {
                    spans.append(Span(kind: .comment, range: index..<end.upperBound))
                    index = end.upperBound
                    continue
                }
                spans.append(Span(kind: .comment, range: index..<line.endIndex))
                isInBlockComment = true
                break
            }
            if language.quotes.contains(character) {
                let end = endOfString(in: line, from: index)
                spans.append(Span(kind: .string, range: index..<end))
                index = end
                continue
            }
            if character.isLetter || character == "_" || character.isNumber {
                let end = line[index...].firstIndex { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
                    ?? line.endIndex
                let wordEnd = character.isNumber
                    ? end
                    : line[index..<end].firstIndex(of: ".") ?? end
                let word = line[index..<wordEnd]
                if character.isNumber {
                    spans.append(Span(kind: .number, range: index..<wordEnd))
                } else if keywords.contains(String(word)) {
                    spans.append(Span(kind: .keyword, range: index..<wordEnd))
                }
                index = wordEnd
                continue
            }
            index = line.index(after: index)
        }
        return spans
    }

    /// Where the string opened by the quote at `start` ends: after its closing quote, else at the end of the line.
    private static func endOfString(in line: String, from start: String.Index) -> String.Index {
        let quote = line[start]
        var index = line.index(after: start)
        while index < line.endIndex {
            if line[index] == "\\" {
                index = line.index(after: index)
                guard index < line.endIndex else { break }
            } else if line[index] == quote {
                return line.index(after: index)
            }
            index = line.index(after: index)
        }
        return line.endIndex
    }

    /// The keywords of Swift, JavaScript and TypeScript, Python, Go, Rust, C, Java and the shell, together.
    private static let keywords: Set<String> = [
        "actor", "and", "any", "as", "async", "await", "break", "case", "catch", "chan", "char", "class", "const",
        "continue", "crate", "def", "default", "defer", "del", "do", "done", "double", "dyn", "elif", "else", "enum",
        "esac", "except", "export", "extends", "extension", "extern", "false", "fi", "final", "finally", "float",
        "fn", "for", "from", "func", "function", "go", "guard", "if", "impl", "implements", "import", "in", "init",
        "inout", "int", "interface", "is", "lambda", "let", "local", "long", "loop", "match", "mod", "mut", "new",
        "nil", "None", "nonisolated", "not", "null", "of", "open", "or", "package", "pass", "private", "protocol",
        "pub", "public", "raise", "range", "return", "self", "Self", "some", "static", "struct", "super", "switch",
        "then", "this", "throw", "throws", "trait", "true", "True", "False", "try", "type", "typedef", "typeof",
        "undefined", "unsafe", "use", "var", "void", "where", "while", "with", "yield",
    ]
}
