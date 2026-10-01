import Foundation

/// A Richiesta di permesso: `claude` wants to use a tool that nothing allows yet, and waits for the user.
///
/// Every text comes from `claude`, an MCP server or the model, cleaned by the bridge: shown verbatim, never trusted.
nonisolated struct PermissionRequest: Identifiable, Equatable, Hashable, Sendable, Decodable {
    /// The tool of a Richiesta "Rete: host": a sandboxed command wants a host outside the Sandbox's domains.
    static let networkTool = "SandboxNetworkAccess"

    /// The bridge's id of the Richiesta, which its answer carries back.
    let id: String
    /// The tool's name, such as `Bash`, `Edit` or `mcp__server__tool`.
    let tool: String
    /// The shell command, for `Bash`.
    var command: String?
    /// The file or folder the tool works on.
    var path: String?
    /// The address, for `WebFetch`.
    var url: String?
    /// The host a sandboxed command wants to reach, for a Richiesta "Rete: host".
    var host: String?
    /// The sentence `claude` would show, such as "Claude wants to read foo.txt".
    var title: String?
    /// What `claude` says the tool will do.
    var detail: String?
    /// The path outside the allowed folders that made `claude` ask.
    var blockedPath: String?
    /// Where an MCP tool's server comes from: `sdk` for Bubo's own, anything else from a configuration.
    var mcpSource: String?
    /// Whether a subagent asks, not the Sessione's main thread.
    var isFromSubagent = false
    /// Whether `claude` says a single keystroke must not approve it.
    var defaultsToNo = false
    /// Whether `claude` says no lasting permission may come from it.
    var suppressesRule = false
    /// Whether a command asks to run outside the Sandbox: only No and Solo ora, never a lasting permission.
    var isOutsideSandbox = false

    private enum CodingKeys: String, CodingKey {
        case request, tool, command, path, url, host, title, description, blockedPath, mcpSource, fromSubagent, defaultToNo,
             suppressAlwaysAllowRule, outsideSandbox
    }

    init(id: String, tool: String, command: String? = nil, path: String? = nil, url: String? = nil, host: String? = nil) {
        self.id = id
        self.tool = tool
        self.command = command
        self.path = path
        self.url = url
        self.host = host
    }

    /// The command, file, address or host the call works on, as shown before approving it.
    var subject: String? { command ?? path ?? url ?? host }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .request)
        tool = try container.decode(String.self, forKey: .tool)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .description)
        blockedPath = try container.decodeIfPresent(String.self, forKey: .blockedPath)
        mcpSource = try container.decodeIfPresent(String.self, forKey: .mcpSource)
        isFromSubagent = try container.decodeIfPresent(Bool.self, forKey: .fromSubagent) ?? false
        defaultsToNo = try container.decodeIfPresent(Bool.self, forKey: .defaultToNo) ?? false
        suppressesRule = try container.decodeIfPresent(Bool.self, forKey: .suppressAlwaysAllowRule) ?? false
        isOutsideSandbox = try container.decodeIfPresent(Bool.self, forKey: .outsideSandbox) ?? false
    }
}

/// The user's answer to a Richiesta di permesso.
nonisolated enum PermissionAnswer: Equatable, Sendable {
    /// No.
    case deny
    /// Solo ora: this call only.
    case allowOnce
    /// Per questa Sessione: this call, and the same one again in the Sessione until Bubo quits.
    case allowForSession
    /// Sempre in questo Progetto: this call, and a Regola di permesso saved in the Progetto for every later one.
    case allowInProject

    /// Whether the call may run.
    var allows: Bool { self != .deny }
}
