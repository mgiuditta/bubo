import Foundation

/// The components of a plugin, from the first source that knows them (spec 20, Fiducia).
nonisolated struct PluginInventory: Sendable, Equatable {
    /// The components, by kind, then by name.
    var components: [PluginComponent]

    /// Creates an inventory of `components`, without duplicates, sorted by kind and name.
    init(components: [PluginComponent]) {
        let kinds = PluginComponent.Kind.allCases
        self.components = Array(Set(components)).sorted { lhs, rhs in
            let left = kinds.firstIndex(of: lhs.kind) ?? 0, right = kinds.firstIndex(of: rhs.kind) ?? 0
            return left == right ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : left < right
        }
    }

    /// "solo testo" or "esegue codice".
    var trust: PluginTrust { runsOutsideSandbox ? .runsCode : .textOnly }

    /// Whether a hook, a stdio MCP server, an LSP server, `bin/` or a monitor runs on the Mac.
    var runsOutsideSandbox: Bool { components.contains(where: \.runsCode) }

    /// The trust label of a plugin whose inventory is `inventory`: unknown without one.
    static func trust(of inventory: PluginInventory?) -> PluginTrust {
        inventory?.trust ?? .unknown
    }

    // MARK: Sources

    /// The inventory of `entry`: its installed folder, then its relative source in `marketplace`'s clone, then the
    /// official cache. Never throws: with no source it is `nil`, and the trust unknown.
    @concurrent static func inventory(of entry: PluginEntry, marketplace: Marketplace?,
                                      officialCache: OfficialCatalogCache?) async -> PluginInventory? {
        let fileManager = FileManager.default
        let declared = entry.declaredComponents
        if let folder = entry.installations.lazy.compactMap(\.installPath).first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return PluginInventory(components: reading(pluginAt: folder).components + declared)
        }
        if case let .relative(path) = entry.source, let clone = marketplace?.installLocation {
            let folder = clone.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
            if folder.path.hasPrefix(clone.standardizedFileURL.path), fileManager.fileExists(atPath: folder.path) {
                return PluginInventory(components: reading(pluginAt: folder).components + declared)
            }
        }
        if let cached = officialCache?.inventory(of: entry.id) {
            return PluginInventory(components: cached.components + declared)
        }
        return nil
    }

    /// The inventory of the version `entry`'s Marketplace offers now, never of the installed one: its relative source
    /// in `marketplace`'s clone, then the official cache; `nil` when nothing says, and the new code is unknown.
    @concurrent static func latestInventory(of entry: PluginEntry, marketplace: Marketplace?,
                                            officialCache: OfficialCatalogCache?) async -> PluginInventory? {
        var latest = entry
        latest.installations = []
        return await inventory(of: latest, marketplace: marketplace, officialCache: officialCache)
    }

    /// Reads a plugin folder: `plugin.json` with custom paths, `skills/`, `commands/`, `agents/`, `hooks/hooks.json`,
    /// `.mcp.json`, `.lsp.json`, `bin/`, `monitors/monitors.json`. A missing or broken file adds nothing.
    static func reading(pluginAt folder: URL) -> PluginInventory {
        let manifest = json(at: folder.appending(path: ".claude-plugin/plugin.json")) as? [String: Any] ?? [:]
        var components: [PluginComponent] = []

        func paths(_ value: Any?) -> [URL] {
            let strings = (value as? String).map { [$0] } ?? (value as? [String] ?? [])
            return strings.map { folder.appending(path: $0) }
        }
        for skills in [folder.appending(path: "skills", directoryHint: .isDirectory)] + paths(manifest["skills"]) {
            components += skillNames(in: skills).map(PluginComponent.skill)
        }
        for commands in [folder.appending(path: "commands", directoryHint: .isDirectory)] + paths(manifest["commands"]) {
            components += markdownNames(in: commands).map(PluginComponent.command)
        }
        for agents in [folder.appending(path: "agents", directoryHint: .isDirectory)] + paths(manifest["agents"]) {
            components += markdownNames(in: agents).map(PluginComponent.agent)
        }

        /// The JSON of `value`: a path to a file of the plugin, a list of them, or the object itself.
        func declared(_ value: Any?, defaultFile: String) -> [Any] {
            switch value {
            case nil: [json(at: folder.appending(path: defaultFile))].compactMap { $0 }
            case let path as String: [json(at: folder.appending(path: path))].compactMap { $0 }
            case let list as [Any]: list.flatMap { declared($0, defaultFile: defaultFile) }
            case let object?: [object]
            }
        }
        components += declared(manifest["hooks"], defaultFile: "hooks/hooks.json").flatMap(hooks(in:))
        components += declared(manifest["mcpServers"], defaultFile: ".mcp.json").flatMap(mcpServers(in:))
        components += declared(manifest["lspServers"], defaultFile: ".lsp.json").flatMap(lspServers(in:))
        components += declared(manifest["monitors"], defaultFile: "monitors/monitors.json").flatMap(monitors(in:))
        components += executables(in: folder.appending(path: "bin", directoryHint: .isDirectory)).map(PluginComponent.executable)
        return PluginInventory(components: components)
    }

    // MARK: Declarations

    /// The hooks of a `hooks.json`, or of a `hooks` object: one per event.
    static func hooks(in json: Any) -> [PluginComponent] {
        guard var object = json as? [String: Any] else { return [] }
        if let inner = object["hooks"] as? [String: Any] { object = inner }
        return object.keys.map { PluginComponent.hook(event: $0) }
    }

    /// The MCP servers of a `.mcp.json`, or of an `mcpServers` object; remote when it has a URL.
    static func mcpServers(in json: Any) -> [PluginComponent] {
        guard var object = json as? [String: Any] else { return [] }
        if let inner = object["mcpServers"] as? [String: Any] { object = inner }
        return object.map { name, configuration in
            let configuration = configuration as? [String: Any] ?? [:]
            let isRemote = configuration["url"] != nil || ["http", "sse", "ws"].contains(configuration["type"] as? String ?? "")
            return .mcpServer(name: name, isRemote: isRemote)
        }
    }

    /// The LSP servers of a `.lsp.json`, or of an `lspServers` object.
    static func lspServers(in json: Any) -> [PluginComponent] {
        guard var object = json as? [String: Any] else { return [] }
        if let inner = object["lspServers"] as? [String: Any] { object = inner }
        return object.keys.map(PluginComponent.lspServer)
    }

    /// The monitors of a `monitors.json`: a list of objects with a name, or an object by name.
    static func monitors(in json: Any) -> [PluginComponent] {
        if let list = json as? [Any] {
            return list.enumerated().map { index, monitor in
                .monitor((monitor as? [String: Any])?["name"] as? String ?? "\(index + 1)")
            }
        }
        guard var object = json as? [String: Any] else { return [] }
        if let inner = object["monitors"] { return monitors(in: inner) }
        object.removeValue(forKey: "$schema")
        return object.keys.map(PluginComponent.monitor)
    }

    // MARK: Files

    private static func json(at file: URL) -> Any? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles)) ?? []
    }

    /// The skills under `folder`: subfolders with a `SKILL.md`, or `folder` itself when it is one.
    private static func skillNames(in folder: URL) -> [String] {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: folder.appending(path: "SKILL.md").path) { return [folder.lastPathComponent] }
        return contents(of: folder).filter { fileManager.fileExists(atPath: $0.appending(path: "SKILL.md").path) }
            .map(\.lastPathComponent)
    }

    /// The Markdown files of `folder` and of its subfolders by name, or `folder` itself when it is one.
    private static func markdownNames(in folder: URL) -> [String] {
        if folder.pathExtension == "md" {
            return FileManager.default.fileExists(atPath: folder.path) ? [folder.deletingPathExtension().lastPathComponent] : []
        }
        let paths = FileManager.default.enumerator(atPath: folder.path)?.compactMap { $0 as? String } ?? []
        return paths.filter { $0.hasSuffix(".md") }.map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
    }

    /// The executable files of `bin/`.
    private static func executables(in folder: URL) -> [String] {
        contents(of: folder).filter { file in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) && !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: file.path)
        }
        .map(\.lastPathComponent)
    }
}
