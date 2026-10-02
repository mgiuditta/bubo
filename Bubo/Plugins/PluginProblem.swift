/// What puts a plugin in Da sistemare, read only: the actions arrive with #209 and #210.
nonisolated enum PluginProblem: Sendable, Equatable {
    /// `errors` of `claude plugin list --json`.
    case loadFailed(PluginID, message: String)
    /// Enabled in `.claude/settings.json` of the Progetto, missing from `installed_plugins.json`.
    case missingProjectPlugin(PluginID)

    /// The plugin with the problem.
    var plugin: PluginID {
        switch self {
        case let .loadFailed(plugin, _), let .missingProjectPlugin(plugin): plugin
        }
    }
}
