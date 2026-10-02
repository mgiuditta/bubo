import Foundation

/// A Marketplace registered in Claude Code.
nonisolated struct Marketplace: Identifiable, Sendable, Equatable {
    /// The name the plugins' identifiers end with.
    let name: String
    /// The clone, or the local folder of a Marketplace added from disk; `nil` when only `claude` knows it, such as
    /// one hosted on claude.ai, which Bubo shows but never removes.
    var installLocation: URL?
    /// The settings that declare it in `extraKnownMarketplaces`, in the order user, project, local; empty when only
    /// `known_marketplaces.json` has it.
    var declaredScopes: [PluginScope] = []

    var id: String { name }

    /// Anthropic's official Marketplace, which Bubo registers only after an explicit click (spec 20).
    static let official = (name: "claude-plugins-official", source: "anthropics/claude-plugins-official")
    /// Anthropic's community Marketplace, only when the user asks for it.
    static let community = (name: "claude-community", source: "anthropics/claude-plugins-community")

    /// Whether Bubo can remove it: not when only `claude` knows it.
    var isRemovable: Bool { installLocation != nil }

    /// The scope `claude plugin marketplace remove` should name to take it away from `scope` only; `nil`, meaning
    /// every scope, when `scope` is `nil` or the last one declaring it. Only then `claude` uninstalls its plugins.
    func removalScope(_ scope: PluginScope?) -> PluginScope? {
        guard let scope, declaredScopes.contains(where: { $0 != scope }) else { return nil }
        return scope
    }
}
