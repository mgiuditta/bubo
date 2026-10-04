import Foundation
import Testing
@testable import Bubo

/// Install, Disattiva, Attiva and Disinstalla with the user's real `claude`, in a temporary `HOME`: never the real
/// `~/.claude`, no network (a Marketplace in a local folder), no model turn. Skipped without `claude`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(3)), .enabled(if: LiveClaude.found != nil, "Serve claude"))
struct PluginCLILiveTests {
    static var claude: URL? { LiveClaude.found }

    let home: PluginHome
    /// The temporary home, as a real path, like `claude` writes it.
    let root: URL
    let environment: [String: String]
    let main: URL
    let catalog: PluginCatalog
    let cli: PluginCLI
    let plugin = PluginID(name: "uno", marketplace: "prova")

    init() async throws {
        home = try PluginHome()
        root = URL(filePath: TrustGate.realPath(home.home.path), directoryHint: .isDirectory)
        environment = PluginListing.environment(base: ["HOME": root.path])
        let marketplace = root.appending(path: "mercato", directoryHint: .isDirectory)
        try home.write(["name": "uno", "version": "1.0.0"], at: marketplace.appending(path: "plugins/uno/.claude-plugin/plugin.json").path)
        try home.write(Data("---\nname: ciao\ndescription: Saluta\n---\nciao\n".utf8),
                       at: marketplace.appending(path: "plugins/uno/skills/ciao/SKILL.md").path)
        try home.write(["name": "prova", "owner": ["name": "Prova"], "plugins": [["name": "uno", "source": "./plugins/uno"]]],
                       at: marketplace.appending(path: ".claude-plugin/marketplace.json").path)
        main = try PluginCLITests.repository(in: root, worktrees: ["uno", "due", "tre"])

        let claude = try #require(Self.claude)
        let added = try await ProcessRunner.disclaimed(environment: environment, in: root)
            .run(claude, ["plugin", "marketplace", "add", marketplace.path])
        try #require(added.exitCode == 0, "marketplace add: \(added.standardOutput)")

        let environment = environment
        let locator = ClaudeLocator(isExecutable: { $0 == claude })
        cli = PluginCLI.live(locator: locator, environment: environment)
        catalog = PluginCatalog(folders: PluginFolders.current(home: root, environment: [:]),
                                listing: .live(locator: locator) { .disclaimed(environment: environment, in: $0) },
                                cli: cli)
    }

    @Test func afterEveryActionBuboShowsWhatClaudeLists() async throws {
        let following = Task { await catalog.follow(project: root.appending(path: "wt-uno")) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot != nil }

        let actions: [PluginCommand] = [
            .install(plugin, scope: .user),
            .disable(plugin, scope: .user),
            .enable(plugin, scope: .user),
            .install(plugin, scope: .project),
            .disable(plugin, scope: .local),
            .enable(plugin, scope: .local),
            .uninstall(plugin, scope: .project, keepingData: false),
            .prune(scope: .project),
            .uninstall(plugin, scope: .user, keepingData: false),
        ]
        for action in actions {
            let result = try await catalog.perform(action)
            #expect(result.succeeded, "\(action.arguments): \(result.message)")
            // A reading started by FSEvents during the command may land just after it.
            let listed = try await claudeList()
            try await waitForCondition(timeout: .seconds(5)) { bubo() == listed }
            #expect(bubo() == listed, "\(action.arguments)")
        }
        #expect(bubo().isEmpty)
    }

    @Test func threeWorktreesLeaveNoDuplicateInstallation() async throws {
        for worktree in ["uno", "due", "tre"] {
            for scope in [PluginScope.project, .local] {
                let result = try await cli.perform(.install(plugin, scope: scope), project: root.appending(path: "wt-\(worktree)"))
                #expect(result.succeeded, "\(worktree) \(scope): \(result.message)")
            }
        }
        let data = try Data(contentsOf: PluginFolders.current(home: root, environment: [:]).installedPlugins)
        let plugins = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["plugins"] as? [String: Any])
        let installations = try #require(plugins[plugin.description] as? [[String: Any]])
        let keys = installations.map { "\($0["scope"] ?? "") \($0["projectPath"] ?? "")" }
        #expect(keys.count == Set(keys).count, "\(keys)")
        #expect(installations.count == 2)
        #expect(installations.allSatisfy { ($0["projectPath"] as? String).map(TrustGate.realPath) == TrustGate.realPath(main.path) })
    }

    @Test func removingTheMarketplaceTakesEveryPluginTheConfirmationListed() async throws {
        let following = Task { await catalog.follow(project: main) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot != nil }
        let folder = root.appending(path: "mercato").path

        // Declared in the Progetto too: taken from the user's settings only, the plugins stay.
        #expect(try await catalog.perform(.addMarketplace(source: folder, scope: .project)).succeeded)
        #expect(try await catalog.perform(.install(plugin, scope: .user)).succeeded)
        #expect(try await catalog.perform(.install(plugin, scope: .project)).succeeded)
        try await waitForCondition { catalog.snapshot?.marketplace(named: "prova")?.declaredScopes == [.user, .project] }
        var marketplace = try #require(catalog.snapshot?.marketplace(named: "prova"))
        #expect(try await catalog.perform(.removeMarketplace(name: "prova", scope: marketplace.removalScope(.user))).succeeded)
        try await waitForCondition { catalog.snapshot?.marketplace(named: "prova")?.declaredScopes == [.project] }
        #expect(try await claudeList().keys.contains(plugin))

        // The last declaration: what the confirmation lists is what `claude` uninstalls.
        marketplace = try #require(catalog.snapshot?.marketplace(named: "prova"))
        let listed = try #require(catalog.snapshot).pluginsRemoved(with: marketplace)
        #expect(listed == [plugin])
        let result = try await catalog.perform(.removeMarketplace(name: "prova", scope: marketplace.removalScope(.project)))
        #expect(result.succeeded, "\(result.message)")
        let data = try Data(contentsOf: PluginFolders.current(home: root, environment: [:]).installedPlugins)
        let left = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["plugins"] as? [String: Any] ?? [:]
        #expect(left.keys.filter { $0.hasSuffix("@prova") }.isEmpty)
        try await waitForCondition { catalog.snapshot?.marketplace(named: "prova") == nil }

        let wrong = try await catalog.perform(.addMarketplace(source: "non/un/repo///", scope: .user))
        #expect(!wrong.succeeded)
        #expect(!wrong.message.isEmpty)
    }

    // MARK: Helpers

    /// The installed plugins as the window shows them: scopes and whether it is on.
    private func bubo() -> [PluginID: Installed] {
        let entries = catalog.snapshot?.plugins.filter(\.isInstalled) ?? []
        return Dictionary(uniqueKeysWithValues: entries.map {
            ($0.id, Installed(scopes: Set($0.installations.map(\.scope.rawValue)), isEnabled: $0.isEnabled))
        })
    }

    /// The installed plugins as `claude plugin list --json` prints them in the main checkout.
    private func claudeList() async throws -> [PluginID: Installed] {
        let claude = try #require(Self.claude)
        let output = try await ProcessRunner.disclaimed(environment: environment, in: main).run(claude, ["plugin", "list", "--json"])
        let list = try #require(PluginList(output: output.standardOutput))
        let counted = list.installed.filter { item in
            item.projectPath.map { PluginInstallation.isSameFolder($0, main) } ?? true
        }
        return Dictionary(grouping: counted, by: \.id).mapValues { items in
            Installed(scopes: Set(items.map(\.scope)), isEnabled: items.contains(where: \.isEnabled))
        }
    }

    private struct Installed: Equatable {
        var scopes: Set<String>
        var isEnabled: Bool
    }
}

/// The user's `claude`, where the app looks for it first; `nil` when it is not installed.
nonisolated enum LiveClaude {
    static let found: URL? = ["\(URL.homeDirectory.path)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
}
