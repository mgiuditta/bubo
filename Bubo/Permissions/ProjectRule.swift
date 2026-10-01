import Foundation

/// A Regola di permesso "Sempre in questo Progetto": the narrowest `permissions.allow` rule the CLI syntax has for a
/// Richiesta, written as the CLI writes it.
///
/// Only three kinds exist, each never wider than what the user saw: a Bash command exactly as shown, the site of a
/// `WebFetch`, one MCP tool. File edits stay per Sessione, as in the CLI.
nonisolated struct ProjectRule: Hashable, Sendable {
    /// What the rule allows.
    enum Scope: Hashable, Sendable {
        /// This command, character for character.
        case command(String)
        /// Every page of this host.
        case site(String)
        /// Every call to this MCP tool.
        case tool(String)
    }

    let scope: Scope

    /// The rule that `request` would give; `nil` when no CLI rule could be as narrow as it.
    init?(_ request: PermissionRequest) {
        switch request.tool {
        case "Bash":
            // An unescaped `*` makes a wildcard and a final `:*` a prefix: such a command has no exact rule.
            guard let command = request.command,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !command.contains("*"), !command.contains("\0")
            else { return nil }
            scope = .command(command)
        case "WebFetch":
            guard let host = request.url.flatMap({ URL(string: $0)?.host(percentEncoded: true)?.lowercased() }),
                  host.wholeMatch(of: /[a-z0-9]([a-z0-9.-]*[a-z0-9])?/) != nil
            else { return nil }
            scope = .site(host)
        default:
            guard request.tool.wholeMatch(of: /mcp__[A-Za-z0-9_-]+__[A-Za-z0-9_-]+/) != nil else { return nil }
            scope = .tool(request.tool)
        }
    }

    /// The rule as it goes in `permissions.allow`, such as `Bash(npm test)`.
    ///
    /// Backslashes and parentheses in the content are escaped as the CLI does, so it reads back the same content.
    var text: String {
        switch scope {
        case let .command(command): "Bash(\(Self.escaped(command)))"
        case let .site(host): "WebFetch(domain:\(host))"
        case let .tool(name): name
        }
    }

    private static func escaped(_ content: String) -> String {
        content.replacing("\\", with: "\\\\").replacing("(", with: "\\(").replacing(")", with: "\\)")
    }

    /// Whether `text` has the shape the CLI reads as a rule: `Tool` or `Tool(content)`, with the content not empty.
    static func isWellFormed(_ text: String) -> Bool {
        guard let open = text.firstIndex(of: "(") else { return !text.isEmpty && !text.contains(")") }
        let name = text[..<open]
        return !name.isEmpty && !name.contains(")") && text.hasSuffix(")") && text.index(after: open) < text.index(before: text.endIndex)
    }
}
