import Foundation
import Testing
@testable import Bubo

/// The Plugin window's reading of Claude Code's files, with no `claude`.
struct PluginFilesTests {
    enum Unreadable: CaseIterable {
        case missing, broken
    }

    @Test(arguments: Unreadable.allCases)
    func unreadableStateFilesGiveAnEmptySnapshot(_ unreadable: Unreadable) async throws {
        let home = try PluginHome()
        if unreadable == .broken {
            try home.write(Data("{\"plugins\": [".utf8), at: home.folders.installedPlugins.path)
            try home.write(Data("non è JSON".utf8), at: home.folders.knownMarketplaces.path)
            try home.write(Data("[]".utf8), at: home.folders.userSettings.path)
        }
        let snapshot = await PluginSnapshot.read(from: home.folders, project: home.project)
        #expect(snapshot == PluginSnapshot())
    }

    @Test func pluginCacheDirectoryReplacesTheDefaultRoot() {
        let home = URL(filePath: "/Users/qualcuno", directoryHint: .isDirectory)
        let custom = PluginFolders.current(home: home, environment: ["CLAUDE_CODE_PLUGIN_CACHE_DIR": "/Volumes/Cache/plugins"])
        #expect(custom.root.path == "/Volumes/Cache/plugins")
        #expect(custom.installedPlugins.path == "/Volumes/Cache/plugins/installed_plugins.json")
        #expect(custom.userSettings.path == "/Users/qualcuno/.claude/settings.json")
        let standard = PluginFolders.current(home: home, environment: [:])
        #expect(standard.root.path == "/Users/qualcuno/.claude/plugins")
    }

    @Test func marketplacesInstallationsAndSettingsMakeTheSnapshot() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [
            ["name": "revisore", "displayName": "Revisore", "description": "Rivede il codice", "category": "development",
             "source": "./plugins/revisore", "version": "2.0.0"],
            ["name": "lsp", "description": "Un server LSP", "source": "./plugins/lsp", "strict": false,
             "lspServers": ["sourcekit-lsp": ["command": "sourcekit-lsp"]]],
            ["description": "senza nome"],
        ])
        let other = home.home.appending(path: "altro", directoryHint: .isDirectory)
        try home.install([
            "revisore@ufficiale": [home.installation()],
            "lsp@ufficiale": [home.installation(scope: "project", project: other)],
            "orfano@sparito": [home.installation(scope: "local", project: home.project)],
        ])
        try home.enableForUser(["revisore@ufficiale": true, "orfano@sparito": true])
        try home.write(["enabledPlugins": ["orfano@sparito": false]], at: home.folders.projectSettings(of: home.project).local.path)

        let snapshot = await PluginSnapshot.read(from: home.folders, project: home.project)
        #expect(snapshot.marketplaces.map(\.name) == ["ufficiale"])
        #expect(snapshot.plugins.map(\.id.description) == ["lsp@ufficiale", "orfano@sparito", "revisore@ufficiale"])
        let revisore = try #require(snapshot.plugins.first { $0.id.name == "revisore" })
        #expect(revisore.displayName == "Revisore")
        #expect(revisore.isInstalled && revisore.isEnabled)
        #expect(revisore.source == .relative(path: "./plugins/revisore"))
        // Installed for another Progetto: not here.
        let lsp = try #require(snapshot.plugins.first { $0.id.name == "lsp" })
        #expect(!lsp.isInstalled)
        #expect(lsp.declaredComponents == [.lspServer("sourcekit-lsp")])
        // The local settings of the Progetto win over the user's.
        let orphan = try #require(snapshot.plugins.first { $0.id.name == "orfano" })
        #expect(orphan.isInstalled && !orphan.isEnabled)
        #expect(snapshot.problems.isEmpty)
    }

    @Test func aProjectPluginEnabledButNotInstalledIsAProblem() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "formattatore", "source": "./plugins/formattatore"]])
        try home.enableForProject(["formattatore@ufficiale": true, "spento@ufficiale": false])
        let snapshot = await PluginSnapshot.read(from: home.folders, project: home.project)
        let id = try #require(PluginID("formattatore@ufficiale"))
        #expect(snapshot.problems == [.missingProjectPlugin(id)])
        #expect(PluginSidebarItem.initialSelection(in: snapshot) == .toFix)
        // Without a Progetto, nothing is missing.
        let withoutProject = await PluginSnapshot.read(from: home.folders, project: nil)
        #expect(withoutProject.problems.isEmpty)
        #expect(PluginSidebarItem.initialSelection(in: withoutProject) == .installed)
    }

    @Test func theListOfClaudeAddsSyncedPluginsErrorsAndInstallCounts() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "revisore", "source": "./plugins/revisore"]])
        try home.enableForProject(["mancante@ufficiale": true])
        let output = """
            {"installed": [
              {"id": "notes@synced", "version": "unknown", "scope": "synced", "enabled": true, "installPath": "/tmp/synced/notes"},
              {"id": "mancante@ufficiale", "version": "1.0.0", "scope": "user", "enabled": true, "installPath": "/tmp/x",
               "errors": ["MCP server failed to start"]},
              {"id": "prova@inline", "version": "unknown", "scope": "session", "enabled": true, "installPath": "/tmp/p"}
            ],
             "available": [
              {"pluginId": "revisore@ufficiale", "name": "revisore", "marketplaceName": "ufficiale", "source": "./plugins/revisore",
               "installCount": 1200},
              {"pluginId": "remoto@claude-ai", "name": "remoto", "marketplaceName": "claude-ai",
               "source": {"source": "github", "repo": "a/b"}, "description": "Da claude.ai"}
            ]}
            """
        let list = try #require(PluginList(output: "Avviso su stdout\n" + output))
        let snapshot = await PluginSnapshot.read(from: home.folders, project: home.project).merging(list, project: home.project)
        let ids = Set(snapshot.plugins.map(\.id.description))
        #expect(ids == ["notes@synced", "mancante@ufficiale", "revisore@ufficiale", "remoto@claude-ai"])
        #expect(snapshot.plugins.first { $0.id.name == "revisore" }?.installCount == 1200)
        #expect(snapshot.marketplaces.map(\.name) == ["claude-ai", "ufficiale"])
        let missing = try #require(PluginID("mancante@ufficiale"))
        #expect(snapshot.problems == [.loadFailed(missing, message: "MCP server failed to start")])
    }

    @Test(arguments: ["", "non è JSON", "42"])
    func anUnreadableListIsNil(_ output: String) {
        #expect(PluginList(output: output) == nil)
    }

    @Test func anIdentifierSplitsAtTheLastAt() throws {
        let id = try #require(PluginID("@scope/pacchetto@mercato"))
        #expect(id.name == "@scope/pacchetto")
        #expect(id.marketplace == "mercato")
        #expect(PluginID("senza-chiocciola") == nil)
        #expect(PluginID("nome@") == nil)
        #expect(PluginID("x@synced")?.isSynced == true)
    }
}
