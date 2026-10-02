import Foundation

/// A plugin offered by a Marketplace, installed, or both.
nonisolated struct PluginEntry: Identifiable, Sendable, Equatable {
    let id: PluginID
    var displayName: String
    var summary: String
    var category: String?
    var tags: [String]
    var source: PluginSource
    /// The version the Marketplace entry declares.
    var version: String?
    /// The components the Marketplace entry declares inline (`mcpServers`, `lspServers`, `hooks`), with no file.
    var declaredComponents: [PluginComponent]
    /// Where it is installed: none, or one per scope and Progetto.
    var installations: [PluginInstallation]
    /// How many installed it, when `claude` knows.
    var installCount: Int?

    /// Creates an entry with only its identifier, for a plugin no Marketplace file describes.
    init(id: PluginID, displayName: String? = nil, summary: String = "", category: String? = nil, tags: [String] = [],
         source: PluginSource = .unknown, version: String? = nil, declaredComponents: [PluginComponent] = [],
         installations: [PluginInstallation] = [], installCount: Int? = nil) {
        self.id = id
        self.displayName = displayName ?? id.name
        self.summary = summary
        self.category = category
        self.tags = tags
        self.source = source
        self.version = version
        self.declaredComponents = declaredComponents
        self.installations = installations
        self.installCount = installCount
    }

    /// Whether it is installed in at least one scope that counts here.
    var isInstalled: Bool { !installations.isEmpty }

    /// Whether at least one installation is on.
    var isEnabled: Bool { installations.contains(where: \.isEnabled) }

    /// The scopes it can be uninstalled from, in the order of `PluginScope`: every one but `managed`.
    var uninstallableScopes: [PluginScope] {
        let scopes = Set(installations.map(\.scope))
        return PluginScope.allCases.filter { $0 != .managed && scopes.contains($0) }
    }

    /// The scope Attiva and Disattiva write; `nil` when only the organization manages it.
    ///
    /// `local` for a plugin of the Progetto, so the settings the team shares stay as they are and the change is only
    /// for this person here; `user` otherwise.
    var switchScope: PluginScope? {
        let scopes = Set(installations.map(\.scope))
        if scopes.contains(.local) || scopes.contains(.project) { return .local }
        return scopes.contains(.user) ? .user : nil
    }
}
