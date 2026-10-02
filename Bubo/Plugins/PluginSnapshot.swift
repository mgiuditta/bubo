import Foundation

/// Everything the Plugin window shows, read at once.
nonisolated struct PluginSnapshot: Sendable, Equatable {
    /// The Marketplaces, by name.
    var marketplaces: [Marketplace]
    /// The plugins of every Marketplace and the installed ones, by display name.
    var plugins: [PluginEntry]
    /// What puts a plugin in Da sistemare.
    var problems: [PluginProblem]
    /// Every plugin installed, in any scope and any Progetto: what removing their Marketplace uninstalls.
    var everyInstalled: Set<PluginID>

    /// Creates a snapshot of `marketplaces`, `plugins` and `problems`, sorting them as the window shows them.
    init(marketplaces: [Marketplace] = [], plugins: [PluginEntry] = [], problems: [PluginProblem] = [],
         everyInstalled: Set<PluginID> = []) {
        self.marketplaces = marketplaces.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.plugins = plugins.sorted { lhs, rhs in
            switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
        self.problems = problems
        self.everyInstalled = everyInstalled.union(self.plugins.filter(\.isInstalled).map(\.id))
    }

    /// The plugins `claude plugin marketplace remove` uninstalls with `marketplace`, by name.
    func pluginsRemoved(with marketplace: Marketplace) -> [PluginID] {
        everyInstalled.filter { $0.marketplace == marketplace.name }.sorted()
    }

    /// The Marketplace called `name`.
    func marketplace(named name: String) -> Marketplace? {
        marketplaces.first { $0.name == name }
    }

    // MARK: Reading the files

    /// Reads the files of `folders` and of `project`, off the main actor; a missing or unreadable file is empty.
    ///
    /// Only reads: `known_marketplaces.json`, the `marketplace.json` of each clone, `installed_plugins.json` and the
    /// three settings with `enabledPlugins`.
    @concurrent static func read(from folders: PluginFolders, project: URL?) async -> PluginSnapshot {
        let known = json(at: folders.knownMarketplaces) as? [String: Any] ?? [:]
        let settings = [folders.userSettings] + (project.map { [folders.projectSettings(of: $0).shared, folders.projectSettings(of: $0).local] } ?? [])
        let settingsJSON = settings.map { json(at: $0) as? [String: Any] ?? [:] }
        let declaring = zip([PluginScope.user, .project, .local], settingsJSON).map { scope, file in
            (scope, Set((file["extraKnownMarketplaces"] as? [String: Any] ?? [:]).keys))
        }
        var marketplaces: [Marketplace] = []
        var entries: [PluginID: PluginEntry] = [:]
        for (name, value) in known {
            let location = ((value as? [String: Any])?["installLocation"] as? String).map { URL(filePath: $0, directoryHint: .isDirectory) }
                ?? folders.marketplaces.appending(path: name, directoryHint: .isDirectory)
            // A Marketplace added from a `marketplace.json` file rather than a folder.
            let (folder, manifest) = location.pathExtension == "json"
                ? (location.deletingLastPathComponent().deletingLastPathComponent(), location)
                : (location, location.appending(path: ".claude-plugin/marketplace.json"))
            marketplaces.append(Marketplace(name: name, installLocation: folder,
                                            declaredScopes: declaring.filter { $0.1.contains(name) }.map(\.0)))
            for item in (json(at: manifest) as? [String: Any])?["plugins"] as? [Any] ?? [] {
                guard let entry = entry(from: item, marketplace: name) else { continue }
                entries[entry.id] = entry
            }
        }

        let enabled = settingsJSON.map(enabledPlugins(in:))
        let merged = enabled.reduce(into: [PluginID: Bool]()) { result, file in result.merge(file) { $1 } }

        let installed = installations(at: folders.installedPlugins)
        for (id, installations) in installed {
            let counted = installations.filter { $0.counts(in: project) }.map { installation in
                var installation = installation
                installation.isEnabled = merged[id] ?? false
                return installation
            }
            guard !counted.isEmpty else { continue }
            entries[id, default: PluginEntry(id: id)].installations = counted
        }

        var problems: [PluginProblem] = []
        if project != nil, enabled.count == 3 {
            for (id, isOn) in enabled[1] where isOn && merged[id] == true && entries[id]?.isInstalled != true {
                problems.append(.missingProjectPlugin(id))
                if entries[id] == nil { entries[id] = PluginEntry(id: id) }
            }
        }
        return PluginSnapshot(marketplaces: marketplaces, plugins: Array(entries.values),
                              problems: problems.sorted { $0.plugin < $1.plugin },
                              everyInstalled: Set(installed.filter { !$0.value.isEmpty }.keys))
    }

    /// An entry of a `marketplace.json`; `nil` without a name.
    private static func entry(from item: Any, marketplace: String) -> PluginEntry? {
        guard let item = item as? [String: Any], let name = item["name"] as? String, !name.isEmpty else { return nil }
        let declared = [item["hooks"].map(PluginInventory.hooks(in:)),
                        item["mcpServers"].map(PluginInventory.mcpServers(in:)),
                        item["lspServers"].map(PluginInventory.lspServers(in:))].compactMap { $0 }.flatMap { $0 }
        return PluginEntry(id: PluginID(name: name, marketplace: marketplace),
                           displayName: item["displayName"] as? String,
                           summary: item["description"] as? String ?? "",
                           category: item["category"] as? String,
                           tags: (item["tags"] as? [String] ?? []) + (item["keywords"] as? [String] ?? []),
                           source: PluginSource(json: item["source"]),
                           version: item["version"] as? String,
                           declaredComponents: declared)
    }

    /// The installations of `installed_plugins.json`, by plugin: a list per plugin (version 2) or one object.
    private static func installations(at file: URL) -> [PluginID: [PluginInstallation]] {
        let plugins = (json(at: file) as? [String: Any])?["plugins"] as? [String: Any] ?? [:]
        var result: [PluginID: [PluginInstallation]] = [:]
        for (key, value) in plugins {
            guard let id = PluginID(key) else { continue }
            let items = value as? [Any] ?? [value]
            result[id] = items.compactMap { item in
                guard let item = item as? [String: Any] else { return nil }
                return PluginInstallation(
                    scope: PluginScope(rawValue: item["scope"] as? String ?? "") ?? .user,
                    projectPath: (item["projectPath"] as? String).map { URL(filePath: $0, directoryHint: .isDirectory) },
                    installPath: (item["installPath"] as? String).map { URL(filePath: $0, directoryHint: .isDirectory) },
                    version: item["version"] as? String,
                    gitCommitSha: item["gitCommitSha"] as? String,
                    isEnabled: false)
            }
        }
        return result
    }

    /// `enabledPlugins` of a settings file; empty when the file or the key is missing.
    private static func enabledPlugins(in settings: [String: Any]) -> [PluginID: Bool] {
        let enabled = settings["enabledPlugins"] as? [String: Any] ?? [:]
        var result: [PluginID: Bool] = [:]
        for (key, value) in enabled {
            guard let id = PluginID(key), let isOn = value as? Bool else { continue }
            result[id] = isOn
        }
        return result
    }

    private static func json(at file: URL) -> Any? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: Merging the CLI

    /// The snapshot with what `claude plugin list --json --available` adds for `project`: synced plugins, the
    /// enabled state `claude` computes, load errors, install counts, Marketplaces hosted on claude.ai.
    func merging(_ list: PluginList, project: URL?) -> PluginSnapshot {
        var entries = Dictionary(plugins.map { ($0.id, $0) }) { first, _ in first }
        var marketplaces = self.marketplaces
        var problems = self.problems.filter { if case .loadFailed = $0 { false } else { true } }
        let installed = list.installed.filter { $0.scope != "session" }
        for (id, items) in Dictionary(grouping: installed, by: \.id) {
            let counted = items.map { item in
                PluginInstallation(scope: PluginScope(rawValue: item.scope) ?? .user, projectPath: item.projectPath,
                                   installPath: item.installPath, version: item.version, gitCommitSha: nil,
                                   isEnabled: item.isEnabled)
            }.filter { $0.counts(in: project) }
            guard !counted.isEmpty else { continue }
            if entries[id]?.isInstalled == true {
                let isEnabled = counted.contains(where: \.isEnabled)
                entries[id]?.installations.indices.forEach { entries[id]?.installations[$0].isEnabled = isEnabled }
            } else {
                entries[id, default: PluginEntry(id: id)].installations = counted
            }
            for message in Set(items.flatMap(\.errors)).sorted() {
                problems.append(.loadFailed(id, message: message))
            }
        }
        for item in list.available {
            if entries[item.id] == nil {
                entries[item.id] = PluginEntry(id: item.id, summary: item.summary ?? "", source: item.source,
                                               version: item.version)
            }
            entries[item.id]?.installCount = item.installCount
        }
        // Marketplaces only `claude` knows, such as those hosted on claude.ai; synced plugins have none.
        for name in Set(entries.keys.filter { !$0.isSynced }.map(\.marketplace))
            where !marketplaces.contains(where: { $0.name == name }) {
            marketplaces.append(Marketplace(name: name, installLocation: nil))
        }
        // A missing project plugin that `claude` reports installed after all.
        problems.removeAll { if case let .missingProjectPlugin(id) = $0 { entries[id]?.isInstalled == true } else { false } }
        return PluginSnapshot(marketplaces: marketplaces, plugins: Array(entries.values), problems: problems,
                              everyInstalled: everyInstalled.union(installed.map(\.id)))
    }
}
