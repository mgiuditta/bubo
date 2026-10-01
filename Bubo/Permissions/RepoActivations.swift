import Foundation

/// What a folder's own settings would turn on once trusted, for the trust dialog (#266).
///
/// Every name and command comes from the repo, so it is untrusted text: each one is already
/// escaped, with control, invisible and direction characters shown as `\u{…}`.
nonisolated struct RepoActivations: Equatable, Sendable {
    /// The hook commands, as `Event: command`.
    var hooks: [String] = []
    /// The names of the `env` variables.
    var environment: [String] = []
    /// The `apiKeyHelper` command.
    var apiKeyHelper: String?
    /// The `.mcp.json` servers, as `name: command arguments` or `name: url`.
    var mcpServers: [String] = []
    /// The `permissions.allow` rules.
    var allowRules: [String] = []
    /// The `permissions.additionalDirectories`.
    var additionalDirectories: [String] = []

    /// Whether the folder would turn nothing on.
    var isEmpty: Bool { self == RepoActivations() }

    /// Reads `.claude/settings.json`, `.claude/settings.local.json` and `.mcp.json` in `folder`;
    /// a missing or unreadable file adds nothing.
    init(folder: URL) {
        for name in [".claude/settings.json", ".claude/settings.local.json"] {
            guard let settings = Self.object(at: folder.appending(path: name)) else { continue }
            for (event, groups) in (settings["hooks"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                for group in groups as? [[String: Any]] ?? [] {
                    for hook in group["hooks"] as? [[String: Any]] ?? [] {
                        hooks.append("\(Self.escaped(event)): \(Self.escaped(Self.text(hook["command"] ?? hook["type"])))")
                    }
                }
            }
            environment += (settings["env"] as? [String: Any] ?? [:]).keys.sorted().map(Self.escaped)
            if let helper = settings["apiKeyHelper"] { apiKeyHelper = Self.escaped(Self.text(helper)) }
            let permissions = settings["permissions"] as? [String: Any] ?? [:]
            allowRules += (permissions["allow"] as? [Any] ?? []).map { Self.escaped(Self.text($0)) }
            additionalDirectories += (permissions["additionalDirectories"] as? [Any] ?? []).map { Self.escaped(Self.text($0)) }
        }
        let servers = Self.object(at: folder.appending(path: ".mcp.json"))?["mcpServers"] as? [String: Any] ?? [:]
        mcpServers = servers.sorted { $0.key < $1.key }.map { name, server in
            let server = server as? [String: Any] ?? [:]
            let launch = server["command"].map { [$0] + (server["args"] as? [Any] ?? []) } ?? [server["url"] as Any]
            return "\(Self.escaped(name)): \(Self.escaped(launch.map(Self.text).joined(separator: " ")))"
        }
    }

    /// Creates a list from already escaped entries, for previews and tests.
    init(hooks: [String] = [], environment: [String] = [], apiKeyHelper: String? = nil, mcpServers: [String] = [],
         allowRules: [String] = [], additionalDirectories: [String] = []) {
        self.hooks = hooks
        self.environment = environment
        self.apiKeyHelper = apiKeyHelper
        self.mcpServers = mcpServers
        self.allowRules = allowRules
        self.additionalDirectories = additionalDirectories
    }

    /// `text` with every control, format (zero-width, direction override) and separator character
    /// written as `\n`, `\t` or `\u{…}`, so it reads exactly as the bytes in the file.
    static func escaped(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\\": result += "\\\\"
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator, .unassigned, .privateUse, .surrogate:
                    result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private static func text(_ value: Any?) -> String {
        switch value {
        case let string as String: string
        case nil: ""
        case let value?: String(describing: value)
        }
    }

    private static func object(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
