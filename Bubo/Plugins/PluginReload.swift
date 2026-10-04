import Foundation

/// How Ricarica plugin went in a turn in progress: what `reloadPlugins()` of the Agent SDK answered (spec 20).
struct PluginReload: Equatable, Decodable {
    /// What applying a held reload would change in the turn's tools.
    struct CacheImpact: Equatable, Decodable {
        /// The plugins' MCP servers it would add, as `plugin:<plugin>:<server>`.
        var added: [String]
        /// The plugins' MCP servers it would drop.
        var removed: [String]
        /// How the LSP tool would change (`adds`, `may-add`, `removes`, `may-remove`); `nil` for no change.
        var lsp: String?
    }

    /// The commands the turn has now, or keeps when `isHeld`: those of the plugins among them.
    var commands: [String]
    /// Whether `claude` did not apply the reload because it would lose the prompt cache: Ricarica comunque applies it.
    var isHeld: Bool
    /// What applying it would change; only when `isHeld`.
    var cacheImpact: CacheImpact?

    private enum CodingKeys: String, CodingKey {
        case commands, isHeld = "held", cacheImpact
    }
}
