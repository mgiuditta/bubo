/// A plugin's identifier as the CLI writes it, `name@marketplace`.
nonisolated struct PluginID: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The plugin's name in its Marketplace.
    let name: String
    /// The Marketplace that offers it; `synced` for a plugin synced from claude.ai.
    let marketplace: String

    /// Creates the identifier of `name` in `marketplace`.
    init(name: String, marketplace: String) {
        self.name = name
        self.marketplace = marketplace
    }

    /// Creates an identifier from `name@marketplace`; `nil` without the `@`.
    init?(_ description: String) {
        guard let at = description.lastIndex(of: "@"), at > description.startIndex,
              description.index(after: at) < description.endIndex
        else { return nil }
        self.init(name: String(description[..<at]), marketplace: String(description[description.index(after: at)...]))
    }

    var description: String { "\(name)@\(marketplace)" }

    /// Whether the plugin is synced from claude.ai (`@synced`).
    var isSynced: Bool { marketplace == "synced" }

    static func < (lhs: PluginID, rhs: PluginID) -> Bool { lhs.description < rhs.description }
}
