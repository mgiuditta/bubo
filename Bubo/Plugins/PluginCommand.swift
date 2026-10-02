/// A `claude plugin …` command that changes the plugins, always with an explicit scope (spec 20, Scrittura).
///
/// A `command` source is confirmed only with `--accept-command` and the fingerprint the CLI showed, never with `-y`.
nonisolated enum PluginCommand: Sendable, Equatable {
    /// Installs `plugin` in `scope`, running the command the CLI showed when `accepting` is not `nil`.
    case install(PluginID, scope: PluginScope, accepting: PluginShownCommand? = nil)
    case enable(PluginID, scope: PluginScope)
    case disable(PluginID, scope: PluginScope)
    /// Uninstalls `plugin` from `scope`, keeping `~/.claude/plugins/data/<id>/` when `keepingData`.
    case uninstall(PluginID, scope: PluginScope, keepingData: Bool)
    /// Removes the dependencies of `scope` nothing needs any more. `-y` here confirms only that, never a command.
    case prune(scope: PluginScope)

    /// The arguments after `claude`.
    var arguments: [String] {
        switch self {
        case let .install(plugin, scope, accepted):
            ["plugin", "install", plugin.description, "--scope", scope.rawValue, "--json"]
                + (accepted.map { ["--accept-command", $0.sha256] } ?? [])
        case let .enable(plugin, scope):
            ["plugin", "enable", plugin.description, "--scope", scope.rawValue, "--json"]
        case let .disable(plugin, scope):
            ["plugin", "disable", plugin.description, "--scope", scope.rawValue, "--json"]
        case let .uninstall(plugin, scope, keepingData):
            ["plugin", "uninstall", plugin.description, "--scope", scope.rawValue, "--json"] + (keepingData ? ["--keep-data"] : [])
        case let .prune(scope):
            ["plugin", "prune", "--scope", scope.rawValue, "-y"]
        }
    }

    /// How long `claude` may take: 120 s to install, since the CLI already allows 60 s for `npm ci`; 60 s otherwise.
    var timeout: Duration {
        if case .install = self { .seconds(120) } else { .seconds(60) }
    }

    /// The plugin it acts on; `nil` for `prune`.
    var plugin: PluginID? {
        switch self {
        case let .install(plugin, _, _), let .enable(plugin, _), let .disable(plugin, _), let .uninstall(plugin, _, _): plugin
        case .prune: nil
        }
    }
}
