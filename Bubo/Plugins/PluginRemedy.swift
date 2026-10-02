/// The one action of a Da sistemare box, as `claude plugin` commands (spec 20).
nonisolated enum PluginRemedy: Sendable, Equatable {
    /// Installs the plugin Per questo Progetto, after adding its Marketplace Per me when `marketplaceSource` is set.
    case installForProject(PluginID, marketplaceSource: String?)
    /// Installs the dependency a plugin needs, in the plugin's scope.
    case installDependency(PluginID, scope: PluginScope)
    /// Turns on the dependency a plugin needs, in the scope Attiva writes for it.
    case enableDependency(PluginID, scope: PluginScope)
    /// Turns the plugin off, so the Sessioni stop failing on it.
    case disable(PluginID, scope: PluginScope)
    /// Nothing `claude plugin` can do from here, such as for a plugin the organization manages: the message to copy.
    case copyMessage(String)
    /// Remembers the plugin's code on the Mac as seen: no `claude` command.
    case acknowledge(PluginID)

    /// The action for `problem` of `entry`, knowing the plugins of `snapshot`.
    ///
    /// An unmet dependency is installed, or turned on; any other error turns the plugin off, the one change that
    /// always stops it failing; with no command that helps, the message is to copy.
    init(problem: PluginProblem, entry: PluginEntry?, snapshot: PluginSnapshot) {
        switch problem {
        case let .missingProjectPlugin(id, source):
            self = .installForProject(id, marketplaceSource: source)
            return
        case let .newExecutableCode(id, _):
            // Turned off it runs nothing; Ho visto sits next to it in the box.
            if let entry, entry.isEnabled, let scope = entry.switchScope {
                self = .disable(id, scope: scope)
            } else {
                self = .acknowledge(id)
            }
            return
        case let .loadFailed(id, type, message):
            if PluginProblem.dependencyTypes.contains(type ?? ""), let dependency = Self.dependency(in: message, of: id) {
                if let installed = snapshot.plugins.first(where: { $0.id == dependency }), installed.isInstalled {
                    if !installed.isEnabled, let scope = installed.switchScope {
                        self = .enableDependency(dependency, scope: scope)
                        return
                    }
                } else {
                    let scope = entry?.installations.map(\.scope).first { $0 != .managed } ?? .user
                    self = .installDependency(dependency, scope: scope)
                    return
                }
            }
            if let entry, entry.isEnabled, let scope = entry.switchScope {
                self = .disable(id, scope: scope)
            } else {
                self = .copyMessage(message)
            }
        }
    }

    /// The commands, in order; empty for ``copyMessage(_:)`` and ``acknowledge(_:)``.
    var commands: [PluginCommand] {
        switch self {
        case let .installForProject(id, source):
            (source.map { [.addMarketplace(source: $0, scope: .user)] } ?? []) + [.install(id, scope: .project)]
        case let .installDependency(id, scope): [.install(id, scope: scope)]
        case let .enableDependency(id, scope): [.enable(id, scope: scope)]
        case let .disable(id, scope): [.disable(id, scope: scope)]
        case .copyMessage, .acknowledge: []
        }
    }

    /// The dependency `Dependency "<id>" is not installed …` names, when it is not `plugin` itself.
    static func dependency(in message: String, of plugin: PluginID) -> PluginID? {
        guard let match = message.firstMatch(of: /[Dd]ependency "([^"]+@[^"]+)"/),
              let id = PluginID(String(match.1)), id != plugin
        else { return nil }
        return id
    }
}
