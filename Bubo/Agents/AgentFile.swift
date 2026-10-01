import Foundation

/// A subagent's Markdown file in an `agents/` folder, as its frontmatter declares it (spec 19).
///
/// Bubo reads these files only to show where an agent comes from: `claude` loads them by itself.
nonisolated struct AgentFile: Equatable, Hashable, Sendable {
    /// Where an `agents/` folder is, in the order `claude` gives precedence to a name.
    enum Source: Hashable, Sendable {
        /// A `.claude/agents/` of the Progetto, or of a folder above it inside the repo.
        case project
        /// The user's `~/.claude/agents/`.
        case user
        /// The `agents/` folder of the plugin with this name.
        case plugin(String)
    }

    /// The file.
    let file: URL
    /// The `agents/` folder the file was read from, maybe in one of its subfolders.
    let folder: URL
    let source: Source
    /// The `name` of the frontmatter: an agent's identity comes from it, never from the file's name.
    let name: String
    let description: String
    /// The `model` of the frontmatter; `nil` when it has none.
    let model: String?
    /// The `tools` of the frontmatter; `nil` when it has none, and the agent has every tool.
    let tools: [String]?
    /// The name Claude delegates by: `name`, prefixed by the plugin and its subfolders for a plugin's agent.
    let identifier: String

    /// Reads the agent declared by the frontmatter of `text`, the content of `file`; `nil` without a frontmatter or
    /// without a `name` and a `description`, which `claude` requires.
    ///
    /// - Parameter namespace: The prefix of the agent's identifier, as `plugin:subfolder`; empty outside a plugin.
    init?(text: String, file: URL, folder: URL, source: Source, namespace: [String] = []) {
        guard let fields = Self.frontmatter(of: text),
              case let .text(name)? = fields["name"], !name.isEmpty,
              case let .text(description)? = fields["description"], !description.isEmpty
        else { return nil }
        self.file = file
        self.folder = folder
        self.source = source
        self.name = name
        self.description = description
        if case let .text(model)? = fields["model"], !model.isEmpty { self.model = model } else { model = nil }
        switch fields["tools"] {
        case let .text(tools)?:
            self.tools = tools.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case let .list(tools)?:
            self.tools = tools
        case nil:
            tools = nil
        }
        identifier = (namespace + [name]).joined(separator: ":")
    }

    // MARK: Frontmatter

    /// A value of the frontmatter.
    enum Value: Equatable, Sendable {
        case text(String)
        case list([String])
    }

    /// The top-level fields of the YAML frontmatter at the start of `text`; `nil` when there is none.
    ///
    /// Only the YAML an agent's file uses: plain and quoted scalars, `|` and `>` blocks, `[a, b]` and `- a` lists.
    /// Nested maps, such as `hooks` or `mcpServers`, are skipped.
    static func frontmatter(of text: String) -> [String: Value]? {
        // `\r\n` is one Character, and a newline.
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if let first = lines.first, first.hasPrefix("\u{FEFF}") { lines[0] = String(first.dropFirst()) }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        let body = Array(lines[1..<end])
        var fields: [String: Value] = [:]
        var index = 0
        while index < body.count {
            let line = body[index]
            index += 1
            guard let first = line.first, !first.isWhitespace, first != "#",
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // The lines under the key, more indented than it: a block or a list.
            var nested: [String] = []
            while index < body.count, body[index].isEmpty || body[index].first?.isWhitespace == true {
                nested.append(body[index])
                index += 1
            }
            if rest.hasPrefix("|") || rest.hasPrefix(">") {
                fields[key] = .text(block(nested, folded: rest.hasPrefix(">")))
            } else if rest.isEmpty || rest.hasPrefix("#") {
                let items = nested.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("-") }
                if !items.isEmpty {
                    fields[key] = .list(items.map { scalar($0.dropFirst().trimmingCharacters(in: .whitespaces)) })
                }
            } else if rest.hasPrefix("["), rest.hasSuffix("]") {
                fields[key] = .list(rest.dropFirst().dropLast().split(separator: ",")
                    .map { scalar($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty })
            } else {
                fields[key] = .text(scalar(rest))
            }
        }
        return fields
    }

    /// The text of a `|` block, or of a `>` one when `folded`, without its indentation and the trailing newlines.
    private static func block(_ lines: [String], folded: Bool) -> String {
        let indent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0.isWhitespace }.count }.min() ?? 0
        let content = lines.map { String($0.dropFirst(min(indent, $0.count))) }
        let text = folded
            ? content.split(separator: "", omittingEmptySubsequences: false).map { $0.joined(separator: " ") }
                .joined(separator: "\n")
            : content.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A scalar without its quotes and escapes, or without its trailing comment when plain.
    private static func scalar(_ text: String) -> String {
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            var result = ""
            var escaping = false
            for character in text.dropFirst().dropLast() {
                if escaping {
                    result.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else {
                    result.append(character)
                }
            }
            return result
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacing("''", with: "'")
        }
        if let comment = text.range(of: " #") { return text[..<comment.lowerBound].trimmingCharacters(in: .whitespaces) }
        return text
    }
}
