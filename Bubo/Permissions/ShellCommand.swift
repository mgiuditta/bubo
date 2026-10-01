import Foundation

/// A shell command split the way ``RiskClassifier`` reads it: its simple commands in order, with their words,
/// their output redirections and whether they pipe into the next one; and the commands nested in substitutions.
///
/// Not a shell: just enough of the POSIX grammar to find every command a line would run. Quotes, escapes,
/// `;`, `&&`, `||`, `|`, `&`, subshells, `$(…)`, backticks, `<(…)`, here-documents and comments.
nonisolated struct ShellCommand {
    /// A word after quote removal.
    struct Word: Equatable {
        /// The word's text, with variables and substitutions as written.
        var text = ""
        /// Whether part of the word is only known when the shell runs: a variable or a substitution.
        var isDynamic = false
        /// Whether the word is one expansion, maybe followed by `/`, `/*` or `/.*`: `"$DIR"/*`, `$(pwd)`.
        var isWholeExpansion: Bool { ["\u{0}", "\u{0}/", "\u{0}/*", "\u{0}/.*"].contains(shape) }
        /// The text with each unguarded expansion as a NUL.
        fileprivate var shape = ""
    }

    /// A simple command: its words, where its output goes, and whether its output feeds the next command.
    struct Simple: Equatable {
        var words: [Word] = []
        var outputs: [Word] = []
        var pipesIntoNext = false
    }

    /// The simple commands, in order.
    private(set) var commands: [Simple] = []
    /// The text of every `$(…)`, backtick and process substitution, to read as commands of their own.
    private(set) var substitutions: [String] = []

    /// Splits `text`, or returns `nil` when its quotes or parentheses do not close.
    init?(_ text: String) {
        var parser = Parser(characters: Array(text))
        guard parser.parse() else { return nil }
        commands = parser.commands
        substitutions = parser.substitutions
    }
}

private nonisolated struct Parser {
    let characters: [Character]
    var index = 0
    var commands: [ShellCommand.Simple] = []
    var substitutions: [String] = []
    private var current = ShellCommand.Simple()
    private var word = ShellCommand.Word()
    private var isInWord = false
    private enum Target { case argument, output, ignored }
    private var target = Target.argument
    /// The here-documents whose bodies start after the next newline: delimiter, and whether tabs are stripped.
    private var hereDocuments: [(delimiter: String, stripsTabs: Bool)] = []

    init(characters: [Character]) {
        self.characters = characters
    }

    private func peek(_ offset: Int = 1) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }

    mutating func parse() -> Bool {
        while index < characters.count {
            let character = characters[index]
            switch character {
            case " ", "\t":
                finishWord()
            case "\n":
                finishCommand()
                skipHereDocuments()
            case "#" where !isInWord:
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            case "'":
                guard let end = characters[(index + 1)...].firstIndex(of: "'") else { return false }
                append(String(characters[(index + 1)..<end]))
                index = end
            case "\"":
                guard readDoubleQuoted() else { return false }
            case "\\":
                if let next = peek(), next != "\n" { append(String(next)) }
                index += 1
            case "$":
                guard readExpansion() else { return false }
            case "`":
                guard let end = characters[(index + 1)...].firstIndex(of: "`") else { return false }
                substitutions.append(String(characters[(index + 1)..<end]))
                appendExpansion("`" + String(characters[(index + 1)..<end]) + "`")
                index = end
            case "<" where peek() == "(", ">" where peek() == "(":
                index += 1
                guard let body = readParenthesized() else { return false }
                substitutions.append(body)
                appendExpansion("<(\(body))")
            case ";", "&", "|", "(", ")":
                readOperator(character)
            case "<", ">":
                // A file descriptor right before: `2>`, `1>>`.
                if isInWord, !word.isDynamic, word.text.allSatisfy(\.isNumber) { isInWord = false; word = .init() }
                finishWord()
                readRedirection(character)
            default:
                append(String(character))
            }
            index += 1
        }
        finishCommand()
        return true
    }

    private mutating func append(_ text: String) {
        isInWord = true
        word.text += text
        word.shape += text
    }

    private mutating func appendExpansion(_ text: String, isGuarded: Bool = false) {
        isInWord = true
        word.text += text
        word.isDynamic = true
        word.shape += isGuarded ? text : "\u{0}"
    }

    /// Reads `"…"`, where only `\`, `$` and backticks keep a meaning.
    private mutating func readDoubleQuoted() -> Bool {
        isInWord = true
        index += 1
        while index < characters.count {
            switch characters[index] {
            case "\"":
                return true
            case "\\":
                if let next = peek() { append(String(next)) }
                index += 1
            case "$":
                guard readExpansion() else { return false }
            case "`":
                guard let end = characters[(index + 1)...].firstIndex(of: "`") else { return false }
                substitutions.append(String(characters[(index + 1)..<end]))
                appendExpansion("`" + String(characters[(index + 1)..<end]) + "`")
                index = end
            default:
                append(String(characters[index]))
            }
            index += 1
        }
        return false
    }

    /// Reads what follows a `$`, leaving `index` on its last character.
    private mutating func readExpansion() -> Bool {
        switch peek() {
        case "(" where peek(2) == "(":
            // Arithmetic: no command inside.
            index += 1
            guard let body = readParenthesized() else { return false }
            appendExpansion("$(\(body))")
        case "(":
            index += 1
            guard let body = readParenthesized() else { return false }
            substitutions.append(body)
            appendExpansion("$(\(body))")
        case "{":
            guard let end = characters[index...].firstIndex(of: "}") else { return false }
            let body = String(characters[(index + 2)..<end])
            // `${DIR:?}` stops the shell when DIR is empty.
            appendExpansion("${\(body)}", isGuarded: body.contains(":?"))
            index = end
        case "'":
            // `$'…'`: a string, with C escapes.
            guard let end = characters[(index + 2)...].firstIndex(of: "'") else { return false }
            append(String(characters[(index + 2)..<end]))
            index = end
        case let next? where next.isLetter || next == "_":
            var end = index + 1
            while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                end += 1
            }
            appendExpansion(String(characters[index..<end]))
            index = end - 1
        case let next? where next.isNumber || "@*#?$!-".contains(next):
            appendExpansion("$\(next)")
            index += 1
        default:
            append("$")
        }
        return true
    }

    /// Reads from the `(` at `index` to its matching `)`, leaving `index` there; quotes may hold parentheses.
    private mutating func readParenthesized() -> String? {
        let start = index + 1
        var depth = 0
        var quote: Character?
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                if character == "\\" && open == "\"" { index += 1 } else if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "\\" {
                index += 1
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return String(characters[start..<index]) }
            }
            index += 1
        }
        return nil
    }

    private mutating func readOperator(_ character: Character) {
        finishWord()
        switch character {
        case "|":
            if peek() == "|" {
                index += 1
                finishCommand()
            } else {
                if peek() == "&" { index += 1 }
                current.pipesIntoNext = true
                finishCommand()
            }
        case "&" where peek() == ">":
            index += 1
            readRedirection(">")
        case "&":
            if peek() == "&" { index += 1 }
            finishCommand()
        default:
            if character == ";", peek() == ";" { index += 1 }
            finishCommand()
        }
    }

    /// Reads `>`, `>>`, `>|`, `>&2`, `<`, `<<`, `<<-` and `<<<` at `index`; the next word is where they go.
    private mutating func readRedirection(_ character: Character) {
        if character == ">" {
            if peek() == ">" || peek() == "|" { index += 1 }
            if peek() == "&" {
                // `>&2`, `>&-`: another descriptor, not a file.
                index += 1
                if let next = peek(), next.isNumber || next == "-" { index += 1; return }
            }
            target = .output
            return
        }
        if peek() == "<", peek(2) == "<" {
            index += 2
            target = .ignored
        } else if peek() == "<" {
            index += 1
            let stripsTabs = peek() == "-"
            if stripsTabs { index += 1 }
            hereDocuments.append((delimiter: readDelimiter(), stripsTabs: stripsTabs))
        } else {
            target = .ignored
        }
    }

    /// Reads the delimiter of a here-document, quoted or not, leaving `index` on its last character.
    private mutating func readDelimiter() -> String {
        index += 1
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        var delimiter = ""
        while index < characters.count, !" \t\n;&|<>()".contains(characters[index]) {
            if !"'\"\\".contains(characters[index]) { delimiter.append(characters[index]) }
            index += 1
        }
        index -= 1
        return delimiter
    }

    /// Skips the bodies of the pending here-documents, from the line after `index`.
    private mutating func skipHereDocuments() {
        for document in hereDocuments {
            while index + 1 < characters.count {
                let start = index + 1
                let end = characters[start...].firstIndex(of: "\n") ?? characters.count
                var line = String(characters[start..<end])
                if document.stripsTabs { line = String(line.drop { $0 == "\t" }) }
                index = end
                if line == document.delimiter { break }
            }
        }
        hereDocuments = []
    }

    private mutating func finishWord() {
        guard isInWord else { return }
        switch target {
        case .argument: current.words.append(word)
        case .output: current.outputs.append(word)
        case .ignored: break
        }
        target = .argument
        word = .init()
        isInWord = false
    }

    private mutating func finishCommand() {
        finishWord()
        if !current.words.isEmpty || !current.outputs.isEmpty { commands.append(current) }
        current = .init()
    }
}
