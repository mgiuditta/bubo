import Foundation
import os

/// `plugin-catalog-cache.json`, where Claude Code keeps the components of the official Marketplace's plugins.
///
/// Undocumented: read field by field, and given up at the first surprise, so a new format means "componenti
/// sconosciuti" and never an error.
nonisolated struct OfficialCatalogCache: Sendable, Equatable {
    private let inventories: [PluginID: PluginInventory]

    /// Reads the cache from `data`; `nil` when it does not have the expected shape.
    init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let catalog = root["catalog"] as? [String: Any],
              let plugins = catalog["plugins"] as? [String: Any]
        else { return nil }
        var inventories: [PluginID: PluginInventory] = [:]
        for (key, value) in plugins {
            guard let id = PluginID(key), let components = (value as? [String: Any])?["components"] as? [String: Any]
            else { continue }
            func names(_ kind: String) -> [String] {
                (components[kind] as? [Any] ?? []).compactMap { $0 as? String ?? ($0 as? [String: Any])?["name"] as? String }
            }
            // The cache does not say whether an MCP server is remote: it counts as code on the Mac.
            inventories[id] = PluginInventory(components: names("skills").map(PluginComponent.skill)
                + names("commands").map(PluginComponent.command)
                + names("agents").map(PluginComponent.agent)
                + names("hooks").map { PluginComponent.hook(event: $0) }
                + names("mcpServers").map { PluginComponent.mcpServer(name: $0, isRemote: false) }
                + names("lspServers").map(PluginComponent.lspServer))
        }
        self.inventories = inventories
    }

    /// The components of `plugin`, when the cache has them.
    func inventory(of plugin: PluginID) -> PluginInventory? {
        inventories[plugin]
    }

    /// Reads the cache of `folders`; `nil`, with a line in the log, when it is missing or its format changed.
    @concurrent static func read(from folders: PluginFolders) async -> OfficialCatalogCache? {
        guard let data = try? Data(contentsOf: folders.officialCatalogCache) else { return nil }
        let cache = OfficialCatalogCache(data: data)
        if cache == nil { Logger.plugins.info("Official plugin catalog cache in an unknown format: components unknown") }
        return cache
    }
}

extension Logger {
    /// The plugins' log: no settings content, paths private.
    nonisolated static let plugins = Logger(subsystem: "com.mgiuditta.bubo", category: "plugins")
}
