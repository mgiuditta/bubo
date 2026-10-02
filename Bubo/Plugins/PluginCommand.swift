import Foundation

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
    /// Registers the Marketplace at `source` (`owner/repo`, a git URL or a folder) in `scope`.
    case addMarketplace(source: String, scope: PluginScope)
    /// Removes the Marketplace `name` from `scope`, or from every scope when `nil`: only then `claude` uninstalls
    /// every plugin of it, in every scope and Progetto.
    case removeMarketplace(name: String, scope: PluginScope?)
    /// Saves `values` of the `userConfig` of `plugin`; the ones left out keep theirs. The values go on standard
    /// input, never in the arguments.
    case configure(PluginID, values: PluginOptionValues)

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
        // No `--json` before CLI 2.1.287: the exit code, then `marketplace list --json` to check. `--` so a source
        // or a name starting with a dash is never read as an option.
        case let .addMarketplace(source, scope):
            ["plugin", "marketplace", "add", "--scope", scope.rawValue, "--", source]
        case let .removeMarketplace(name, scope):
            ["plugin", "marketplace", "remove"] + (scope.map { ["--scope", $0.rawValue] } ?? []) + ["--", name]
        case let .configure(plugin, _):
            ["plugin", "configure", plugin.description, "--values-stdin", "--json"]
        }
    }

    /// What `claude` reads on its standard input; `nil` when it reads nothing.
    var input: Data? {
        if case let .configure(_, values) = self { values.json } else { nil }
    }

    /// How long `claude` may take: 120 s to install, since the CLI already allows 60 s for `npm ci`, and to clone a
    /// Marketplace; 60 s otherwise.
    var timeout: Duration {
        switch self {
        case .install, .addMarketplace: .seconds(120)
        default: .seconds(60)
        }
    }

    /// The plugin it acts on; `nil` for `prune` and the Marketplaces.
    var plugin: PluginID? {
        switch self {
        case let .install(plugin, _, _), let .enable(plugin, _), let .disable(plugin, _), let .uninstall(plugin, _, _),
             let .configure(plugin, _): plugin
        case .prune, .addMarketplace, .removeMarketplace: nil
        }
    }
}
