import Foundation

/// A skill the user can call with `/name` wherever a prompt is written: a `SKILL.md` folder or a command `.md` of the
/// user, of an enabled plugin or of the folder the prompt works in (#689).
nonisolated struct Skill: Sendable, Hashable, Identifiable {
    /// Where the skill comes from.
    enum Source: Sendable, Hashable {
        case user, plugin, project
    }

    /// What follows the `/`: `name`, or `plugin:name` for a plugin's, as the CLI shows it.
    let name: String
    /// What the skill is for, from its frontmatter; empty when it says nothing.
    let summary: String
    /// The instructions, without the frontmatter.
    let body: String
    /// The folder of a `SKILL.md`, with its references and scripts; `nil` for a command, a lone file.
    let directory: URL?
    let source: Source

    var id: String { name }

    /// Reads the skill in `file`, called `name` unless its frontmatter names it; `nil` when the file cannot be read.
    init?(file: URL, name: String, directory: URL?, source: Source) {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let (fields, body) = Self.frontmatter(of: text)
        let named = fields["name"].flatMap { $0.isEmpty ? nil : $0 }
        // A plugin's prefix stays: the frontmatter names the skill, the plugin is where it lives.
        if let prefix = name.split(separator: ":", maxSplits: 1).dropLast().first, let named {
            self.name = "\(prefix):\(named)"
        } else {
            self.name = named ?? name
        }
        summary = fields["description"] ?? ""
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.directory = directory
        self.source = source
    }

    /// The `key: value` lines of the YAML frontmatter at the top of `text`, and the text after it; no frontmatter
    /// leaves `text` whole.
    static func frontmatter(of text: String) -> (fields: [String: String], body: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return ([:], text) }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !key.hasPrefix(" ") { fields[key] = value }
        }
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }
}
