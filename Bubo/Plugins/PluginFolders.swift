import Foundation

/// Where Claude Code keeps the plugins' state and the settings with `enabledPlugins`. Bubo only reads them.
nonisolated struct PluginFolders: Sendable, Equatable {
    /// `CLAUDE_CODE_PLUGIN_CACHE_DIR` when set, otherwise `~/.claude/plugins`.
    let root: URL
    /// `~/.claude/settings.json`.
    let userSettings: URL

    /// `installed_plugins.json`.
    var installedPlugins: URL { root.appending(path: "installed_plugins.json") }
    /// `known_marketplaces.json`.
    var knownMarketplaces: URL { root.appending(path: "known_marketplaces.json") }
    /// The clones of the Marketplaces.
    var marketplaces: URL { root.appending(path: "marketplaces", directoryHint: .isDirectory) }
    /// `plugin-catalog-cache.json`, undocumented and optional.
    var officialCatalogCache: URL { root.appending(path: "plugin-catalog-cache.json") }

    /// The folders of the user whose home is `home`, honoring `CLAUDE_CODE_PLUGIN_CACHE_DIR` in `environment`.
    static func current(home: URL = .homeDirectory,
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> PluginFolders {
        let claude = home.appending(path: ".claude", directoryHint: .isDirectory)
        let root = environment["CLAUDE_CODE_PLUGIN_CACHE_DIR"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
            ?? claude.appending(path: "plugins", directoryHint: .isDirectory)
        return PluginFolders(root: root, userSettings: claude.appending(path: "settings.json"))
    }

    /// `.claude/settings.json` and `.claude/settings.local.json` of `project`.
    func projectSettings(of project: URL) -> (shared: URL, local: URL) {
        let folder = project.appending(path: ".claude", directoryHint: .isDirectory)
        return (folder.appending(path: "settings.json"), folder.appending(path: "settings.local.json"))
    }
}
