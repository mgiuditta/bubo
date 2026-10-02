import Foundation
import Testing
@testable import Bubo

/// The components of a plugin and its trust label, from the folder, the Marketplace's clone or the official cache.
struct PluginInventoryTests {
    /// A plugin folder and what it should give.
    nonisolated struct Folder: CustomTestStringConvertible, Sendable {
        let name: String
        let files: [String: String]
        let executables: [String]
        let components: Set<PluginComponent>
        let trust: PluginTrust

        var testDescription: String { name }
    }

    nonisolated static let folders: [Folder] = [
        Folder(name: "solo testo", files: [
            "skills/revisione/SKILL.md": "---\nname: revisione\n---",
            "commands/rivedi.md": "Rivedi",
            "agents/sub/revisore.md": "---\nname: revisore\n---",
            "README.md": "x",
        ], executables: [], components: [.skill("revisione"), .command("rivedi"), .agent("revisore")], trust: .textOnly),
        Folder(name: "hook", files: ["hooks/hooks.json": #"{"hooks": {"PreToolUse": [], "Stop": []}}"#],
               executables: [], components: [.hook(event: "PreToolUse"), .hook(event: "Stop")], trust: .runsCode),
        Folder(name: "MCP stdio", files: [".mcp.json": #"{"mcpServers": {"db": {"command": "node", "args": ["s.js"]}}}"#],
               executables: [], components: [.mcpServer(name: "db", isRemote: false)], trust: .runsCode),
        Folder(name: "MCP remoto", files: [".mcp.json": #"{"mcpServers": {"web": {"type": "http", "url": "https://x.dev/mcp"}}}"#],
               executables: [], components: [.mcpServer(name: "web", isRemote: true)], trust: .textOnly),
        Folder(name: "LSP", files: [".lsp.json": #"{"gopls": {"command": "gopls"}}"#],
               executables: [], components: [.lspServer("gopls")], trust: .runsCode),
        Folder(name: "bin", files: ["bin/README.txt": "x"], executables: ["bin/strumento"],
               components: [.executable("strumento")], trust: .runsCode),
        Folder(name: "monitor", files: ["monitors/monitors.json": #"[{"name": "log", "command": "tail -f x"}]"#],
               executables: [], components: [.monitor("log")], trust: .runsCode),
        Folder(name: "percorsi personalizzati", files: [
            ".claude-plugin/plugin.json": #"""
                {"name": "p", "commands": ["./extra/uno.md"], "agents": "./altri",
                 "hooks": "./config/hooks.json", "mcpServers": {"remoto": {"url": "https://x.dev"}}}
                """#,
            "extra/uno.md": "Uno",
            "altri/due.md": "Due",
            "config/hooks.json": #"{"hooks": {"SessionStart": []}}"#,
        ], executables: [], components: [.command("uno"), .agent("due"), .hook(event: "SessionStart"),
                                         .mcpServer(name: "remoto", isRemote: true)], trust: .runsCode),
    ]

    @Test(arguments: folders)
    func aPluginFolderGivesItsComponentsAndTrust(_ folder: Folder) throws {
        let home = try PluginHome()
        let plugin = home.home.appending(path: "plugin", directoryHint: .isDirectory)
        for (path, text) in folder.files { try home.write(Data(text.utf8), at: plugin.appending(path: path).path) }
        for path in folder.executables {
            let file = plugin.appending(path: path)
            try home.write(Data("#!/bin/sh\n".utf8), at: file.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let inventory = PluginInventory.reading(pluginAt: plugin)
        #expect(Set(inventory.components) == folder.components)
        #expect(inventory.trust == folder.trust)
        #expect(inventory.runsOutsideSandbox == (folder.trust == .runsCode))
    }

    @Test func aRelativeSourceIsReadFromTheMarketplaceClone() async throws {
        let home = try PluginHome()
        try home.addMarketplace("mercato", plugins: [["name": "hooker", "source": "./plugins/hooker"],
                                                     ["name": "evasore", "source": "../../fuori"]])
        let clone = home.folders.marketplaces.appending(path: "mercato", directoryHint: .isDirectory)
        try home.write(Data(#"{"hooks": {"Stop": []}}"#.utf8), at: clone.appending(path: "plugins/hooker/hooks/hooks.json").path)
        let snapshot = await PluginSnapshot.read(from: home.folders, project: nil)
        let marketplace = snapshot.marketplace(named: "mercato")
        let hooker = try #require(snapshot.plugins.first { $0.id.name == "hooker" })
        let inventory = await PluginInventory.inventory(of: hooker, marketplace: marketplace, officialCache: nil)
        #expect(inventory?.components == [.hook(event: "Stop")])
        // A relative source outside the clone is never read.
        let evasore = try #require(snapshot.plugins.first { $0.id.name == "evasore" })
        #expect(await PluginInventory.inventory(of: evasore, marketplace: marketplace, officialCache: nil) == nil)
    }

    @Test func aLocalMarketplaceIsReadFromItsInstallLocation() async throws {
        let home = try PluginHome()
        let local = home.home.appending(path: "sviluppo/mio-mercato", directoryHint: .isDirectory)
        try home.write(["mio": ["source": ["source": "directory", "path": local.path], "installLocation": local.path]],
                       at: home.folders.knownMarketplaces.path)
        try home.write(["name": "mio", "plugins": [["name": "testo", "source": "./testo"]]],
                       at: local.appending(path: ".claude-plugin/marketplace.json").path)
        try home.write(Data("x".utf8), at: local.appending(path: "testo/skills/scrivi/SKILL.md").path)
        let snapshot = await PluginSnapshot.read(from: home.folders, project: nil)
        let entry = try #require(snapshot.plugins.first)
        let inventory = await PluginInventory.inventory(of: entry, marketplace: snapshot.marketplace(named: "mio"),
                                                        officialCache: nil)
        #expect(inventory?.components == [.skill("scrivi")])
        #expect(inventory?.trust == .textOnly)
    }

    enum OfficialCacheFixture: String, CaseIterable {
        case missing, empty, emptyArray, newFields, truncated
    }

    @Test(arguments: OfficialCacheFixture.allCases)
    func aMissingOrChangedOfficialCacheMeansUnknownComponents(_ fixture: OfficialCacheFixture) async throws {
        let home = try PluginHome()
        try home.addMarketplace("claude-plugins-official", plugins: [
            ["name": "remoto", "source": ["source": "url", "url": "https://github.com/a/b.git"]],
        ])
        let file = home.folders.officialCatalogCache.path
        switch fixture {
        case .missing: break
        case .empty: try home.write(Data(), at: file)
        case .emptyArray: try home.write(Data("[]".utf8), at: file)
        case .newFields: try home.write(["version": 2, "catalog": ["entries": ["remoto@claude-plugins-official": [:]]]], at: file)
        case .truncated: try home.write(Data(#"{"version": 1, "catalog": {"plugins": {"remoto@claude-plu"#.utf8), at: file)
        }
        let cache = await OfficialCatalogCache.read(from: home.folders)
        #expect(cache == nil)
        let snapshot = await PluginSnapshot.read(from: home.folders, project: nil)
        let entry = try #require(snapshot.plugins.first)
        let inventory = await PluginInventory.inventory(of: entry, marketplace: snapshot.marketplaces.first, officialCache: cache)
        #expect(PluginInventory.trust(of: inventory) == .unknown)
        #expect(snapshot.problems.isEmpty)
    }

    @Test func theOfficialCacheGivesTheComponentsOfItsPlugins() throws {
        let json = """
            {"version": 1, "catalog": {"plugins": {
              "remoto@claude-plugins-official": {"plugin": "remoto", "components": {
                "skills": [{"name": "scrivi", "chars": {"always_on": 1}}], "commands": [], "agents": [],
                "hooks": ["PreToolUse"], "mcpServers": ["Server"], "lspServers": []}},
              "testo@claude-plugins-official": {"components": {"skills": [{"name": "leggi"}]}},
              "rotto@claude-plugins-official": {"components": 3}
            }}}
            """
        let cache = try #require(OfficialCatalogCache(data: Data(json.utf8)))
        let remoteID = try #require(PluginID("remoto@claude-plugins-official"))
        let remote = try #require(cache.inventory(of: remoteID))
        #expect(Set(remote.components) == [.skill("scrivi"), .hook(event: "PreToolUse"), .mcpServer(name: "Server", isRemote: false)])
        #expect(remote.trust == .runsCode)
        #expect(cache.inventory(of: PluginID(name: "testo", marketplace: "claude-plugins-official"))?.trust == .textOnly)
        #expect(cache.inventory(of: PluginID(name: "rotto", marketplace: "claude-plugins-official")) == nil)
    }

    @Test func theInstalledFolderComesFirstWithTheDeclaredComponents() async throws {
        let home = try PluginHome()
        let installed = home.home.appending(path: "cache/swift-lsp/1.0.0", directoryHint: .isDirectory)
        try home.write(Data("x".utf8), at: installed.appending(path: "README.md").path)
        try home.addMarketplace("ufficiale", plugins: [["name": "swift-lsp", "source": "./plugins/swift-lsp", "strict": false,
                                                        "lspServers": ["sourcekit-lsp": ["command": "sourcekit-lsp"]]]])
        try home.install(["swift-lsp@ufficiale": [home.installation(path: installed)]])
        let snapshot = await PluginSnapshot.read(from: home.folders, project: nil)
        let entry = try #require(snapshot.plugins.first)
        let inventory = await PluginInventory.inventory(of: entry, marketplace: snapshot.marketplaces.first, officialCache: nil)
        #expect(inventory?.components == [.lspServer("sourcekit-lsp")])
        #expect(inventory?.runsOutsideSandbox == true)
    }
}
