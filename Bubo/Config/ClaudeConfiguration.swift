import Foundation

/// The configuration `claude` loads in a folder, as `claude` itself reports it through the bridge.
///
/// Bubo never reads or copies the configuration files: the SDK loads them, and this is what it says it loaded.
nonisolated struct ClaudeConfiguration: Decodable, Equatable, Sendable {
    /// A plugin `claude` loaded.
    struct Plugin: Decodable, Equatable, Sendable {
        let name: String
        /// The version its manifest declares, if any.
        let version: String?
    }

    /// A plugin that did not load, or loaded without one of its parts.
    struct PluginError: Decodable, Equatable, Sendable {
        /// The plugin, as `name@marketplace`.
        let plugin: String
        let message: String
    }

    /// A server MCP and how its connection went.
    struct MCPServer: Decodable, Equatable, Sendable {
        let name: String
        /// `connected`, `failed`, `needs-auth`, `pending` or `disabled`.
        let status: String
        /// Where it is defined: `user`, `project`, `local`, `plugin`, `claudeai` and so on.
        let source: String?
        /// Why it failed, when it did.
        let error: String?

        /// Whether the server waits for an OAuth login, which only the CLI can complete.
        var needsAuthentication: Bool { status == "needs-auth" }
        /// Whether the server is not working.
        var hasFailed: Bool { status == "failed" }
    }

    /// A CLAUDE.md or rules file loaded in the context.
    struct Instructions: Decodable, Equatable, Sendable {
        let path: String
        /// `User`, `Project`, `Local` or `Managed`.
        let type: String
    }

    let skills: [String]
    let plugins: [Plugin]
    let pluginErrors: [PluginError]
    let mcpServers: [MCPServer]
    let instructions: [Instructions]
    /// Whether the Progetto's own settings were loaded: not while its folder is not trusted (`TrustGate`).
    var loadsProject = false

    private enum CodingKeys: String, CodingKey {
        case skills, plugins, pluginErrors, mcpServers, instructions
    }
}
