/// What puts a plugin in Da sistemare, each with one action (spec 20).
nonisolated enum PluginProblem: Sendable, Equatable {
    /// A load error `claude` reports: `errorDetails` of `claude plugin list --json`, or `plugin_errors` of the
    /// `system/init` of a Sessione. `type` comes from an open set, such as `dependency-unsatisfied`; `nil` when unknown.
    case loadFailed(PluginID, type: String? = nil, message: String)
    /// Enabled in `.claude/settings.json` of the Progetto and not installed here. `marketplaceSource` is what
    /// `claude plugin marketplace add` takes when its Marketplace is missing too, as the settings declare it.
    case missingProjectPlugin(PluginID, marketplaceSource: String? = nil)

    /// The plugin with the problem.
    var plugin: PluginID {
        switch self {
        case let .loadFailed(plugin, _, _), let .missingProjectPlugin(plugin, _): plugin
        }
    }

    /// The order of the boxes, lowest first: a missing plugin of the Progetto, an unmet dependency, any other error.
    var gravity: Int {
        switch self {
        case .missingProjectPlugin: 0
        case let .loadFailed(_, type, _): Self.dependencyTypes.contains(type ?? "") ? 1 : 2
        }
    }

    /// The types of a dependency that is missing, turned off, or at a version that does not fit.
    static let dependencyTypes: Set<String> = ["dependency-unsatisfied", "dependency-version-unsatisfied"]

    /// Whether a Sessione's `message` says the plugin is enabled by the Progetto and not installed on this Mac:
    /// `Plugin "<name>" is enabled in project settings but isn't installed here`.
    static func meansNotInstalledHere(_ message: String) -> Bool {
        message.contains("isn't installed here")
    }
}
