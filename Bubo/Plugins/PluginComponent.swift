import Foundation

/// One thing a plugin adds to Claude Code.
nonisolated enum PluginComponent: Sendable, Hashable {
    case skill(String)
    case command(String)
    case agent(String)
    case hook(event: String)
    case mcpServer(name: String, isRemote: Bool)
    case lspServer(String)
    case executable(String)
    case monitor(String)

    /// Whether it runs code on the Mac, outside the sandbox: hooks, stdio MCP servers, LSP servers, `bin/`, monitors.
    var runsCode: Bool {
        switch self {
        case .skill, .command, .agent: false
        case let .mcpServer(_, isRemote): !isRemote
        case .hook, .lspServer, .executable, .monitor: true
        }
    }

    /// The component's name, as the plugin declares it.
    var name: String {
        switch self {
        case let .skill(name), let .command(name), let .agent(name), let .hook(name), let .lspServer(name),
             let .executable(name), let .monitor(name), let .mcpServer(name, _): name
        }
    }

    /// The kind of component, for the inventory's groups.
    var kind: Kind {
        switch self {
        case .skill: .skill
        case .command: .command
        case .agent: .agent
        case .hook: .hook
        case .mcpServer: .mcpServer
        case .lspServer: .lspServer
        case .executable: .executable
        case .monitor: .monitor
        }
    }

    /// The kinds of component, in the order the inventory shows them.
    enum Kind: CaseIterable, Sendable {
        case skill, command, agent, hook, mcpServer, lspServer, executable, monitor

        /// The title of the kind's group.
        var title: LocalizedStringResource {
            switch self {
            case .skill: "Skill"
            case .command: "Comandi"
            case .agent: "Agenti"
            case .hook: "Hook"
            case .mcpServer: "Server MCP"
            case .lspServer: "Server LSP"
            case .executable: "Eseguibili"
            case .monitor: "Monitor"
            }
        }
    }
}
