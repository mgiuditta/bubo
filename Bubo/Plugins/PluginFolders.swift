import CoreServices
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

    /// Each change FSEvents sees of `installed_plugins.json`, `known_marketplaces.json`, the user's settings and the
    /// settings of `projects`, and with `includingMarketplaces` of the Marketplaces' `marketplace.json`, from now on.
    ///
    /// Changes that come while the last one waits are merged into it. Ending the iteration stops FSEvents.
    func changes(in projects: [URL], includingMarketplaces: Bool) -> AsyncStream<Void> {
        let roots = [root, userSettings.deletingLastPathComponent()] + projects
        let files = Set(([installedPlugins, knownMarketplaces, userSettings]
                         + projects.flatMap { [projectSettings(of: $0).shared, projectSettings(of: $0).local] })
            .map { Self.normalized($0.path) })
        let clones = includingMarketplaces ? Self.normalized(marketplaces.path) + "/" : nil
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let watcher = Task(priority: .utility) {
            for await batch in FileEvents.batches(under: roots.map(\.path),
                                                  since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
            where batch.needsRescan || batch.paths.contains(where: { path in
                let path = Self.normalized(path)
                if files.contains(path) { return true }
                guard let clones else { return false }
                return path.hasPrefix(clones) && path.hasSuffix("/.claude-plugin/marketplace.json")
            }) {
                continuation.yield()
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in watcher.cancel() }
        return changes
    }

    /// `path` without the `/private` FSEvents puts before `/var` and `/tmp`.
    private static func normalized(_ path: String) -> String {
        for prefix in ["/private/var/", "/private/tmp/"] where path.hasPrefix(prefix) {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
