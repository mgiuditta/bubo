import Foundation
import Synchronization
import Testing
@testable import Bubo

/// Da sistemare: where the problems come from, their order, and the one action of each. A temporary home and a fake
/// `claude`: nothing touches the real `~/.claude`.
@MainActor
struct PluginProblemsTests {
    nonisolated static let formatter = PluginID(name: "formattatore", marketplace: "ufficiale")
    nonisolated static let base = PluginID(name: "base", marketplace: "ufficiale")

    @Test func onlyAProjectPluginThatNeedsAnInstallationIsMissing() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [
            ["name": "relativo", "source": "./plugins/relativo"],
            ["name": "formattatore", "source": ["source": "github", "repo": "a/formattatore"]],
        ])
        try home.write(["enabledPlugins": ["relativo@ufficiale": true, "formattatore@ufficiale": true,
                                           "cartella@skills-dir": true, "lontano@team": true, "inline@altro": true],
                        "extraKnownMarketplaces": ["team": ["source": ["source": "github", "repo": "azienda/team"]],
                                                   "altro": ["source": ["source": "settings", "plugins": []]]]],
                       at: home.folders.projectSettings(of: home.project).shared.path)

        let snapshot = await PluginSnapshot.read(from: home.folders, project: home.project)

        // A relative plugin loads from its Marketplace; a skills folder needs nothing.
        #expect(snapshot.problems == [
            .missingProjectPlugin(Self.formatter),
            .missingProjectPlugin(PluginID(name: "inline", marketplace: "altro")),
            .missingProjectPlugin(PluginID(name: "lontano", marketplace: "team"), marketplaceSource: "azienda/team"),
        ])
    }

    @Test func theListGivesEachErrorWithItsType() throws {
        let output = """
            {"installed": [{"id": "formattatore@ufficiale", "scope": "user", "enabled": true,
              "errors": ["Dependency \\"base@ufficiale\\" is not installed", "hook failed"],
              "errorDetails": [{"type": "dependency-unsatisfied", "dependency": "base@ufficiale"}, {"type": "hook-load-failed"}]},
             {"id": "vecchio@ufficiale", "scope": "user", "enabled": true, "errors": ["manifest invalid"]}]}
            """
        let list = try #require(PluginList(output: output))
        #expect(list.installed[0].errors == [.init(type: "dependency-unsatisfied", message: #"Dependency "base@ufficiale" is not installed"#),
                                             .init(type: "hook-load-failed", message: "hook failed")])
        #expect(list.installed[1].errors == [.init(type: nil, message: "manifest invalid")])

        let snapshot = PluginSnapshot().merging(list, project: nil)
        // The gravest first: the unmet dependency, then the other errors.
        #expect(snapshot.problems.map(\.gravity) == [1, 2, 2])
    }

    @Test func theErrorsOfTheSessioniJoinTheOnesOfTheList() {
        let listed = PluginSnapshot(plugins: [PluginEntry(id: Self.formatter)], problems: [.loadFailed(Self.formatter, message: "hook failed")])
        let merged = listed.merging([
            .init(plugin: "formattatore@ufficiale", message: "hook failed", type: "hook-load-failed"),
            .init(plugin: "nuovo@ufficiale", message: #"Plugin "nuovo" is enabled in project settings but isn't installed here"#,
                  type: "plugin-not-installed"),
            .init(plugin: "rotto@ufficiale", message: "manifest invalid", type: "manifest-validation-error"),
            .init(plugin: "inline[0]", message: "path not found", type: "path-not-found"),
        ])
        #expect(merged.problems == [
            .missingProjectPlugin(PluginID(name: "nuovo", marketplace: "ufficiale")),
            .loadFailed(Self.formatter, message: "hook failed"),
            .loadFailed(PluginID(name: "rotto", marketplace: "ufficiale"), type: "manifest-validation-error",
                        message: "manifest invalid"),
        ])
        // Every plugin with a problem has a row in Da sistemare.
        #expect(Set(merged.plugins.map(\.id)) == Set(merged.problems.map(\.plugin)))
    }

    @Test func everyProblemHasAnAction() {
        let installed = PluginInstallation(scope: .user, projectPath: nil, installPath: nil, version: nil, gitCommitSha: nil,
                                           isEnabled: true)
        var off = installed
        off.isEnabled = false
        let managed = PluginInstallation(scope: .managed, projectPath: nil, installPath: nil, version: nil, gitCommitSha: nil,
                                         isEnabled: true)
        let formatter = PluginEntry(id: Self.formatter, installations: [installed])
        let missingBase = "Dependency \"base@ufficiale\" is not installed — run `claude plugin install base@ufficiale`"
        let dependency = PluginProblem.loadFailed(Self.formatter, type: "dependency-unsatisfied", message: missingBase)

        #expect(PluginRemedy(problem: .missingProjectPlugin(Self.formatter, marketplaceSource: "a/b"), entry: nil,
                             snapshot: PluginSnapshot()).commands
            == [.addMarketplace(source: "a/b", scope: .user), .install(Self.formatter, scope: .project)])
        #expect(PluginRemedy(problem: dependency, entry: formatter, snapshot: PluginSnapshot(plugins: [formatter]))
            == .installDependency(Self.base, scope: .user))
        let disabledBase = PluginSnapshot(plugins: [formatter, PluginEntry(id: Self.base, installations: [off])])
        #expect(PluginRemedy(problem: dependency, entry: formatter, snapshot: disabledBase) == .enableDependency(Self.base, scope: .user))
        #expect(PluginRemedy(problem: .loadFailed(Self.formatter, type: "hook-load-failed", message: "hook failed"),
                             entry: formatter, snapshot: PluginSnapshot()) == .disable(Self.formatter, scope: .user))
        let byOrganization = PluginEntry(id: Self.formatter, installations: [managed])
        #expect(PluginRemedy(problem: .loadFailed(Self.formatter, message: "x"), entry: byOrganization,
                             snapshot: PluginSnapshot()) == .copyMessage("x"))
    }

    @Test func oneClickAddsTheMarketplaceThenInstallsForTheProgetto() async throws {
        let home = try PluginHome()
        let calls = Mutex<[[String]]>([])
        let cli = PluginCLI(run: { arguments, _, _ in
            calls.withLock { $0.append(arguments) }
            if arguments.starts(with: ["plugin", "marketplace", "list"]) {
                return ProcessOutput(exitCode: 0, standardOutput: #"[{"name": "team"}]"#)
            }
            if arguments.starts(with: ["plugin", "marketplace", "add"]) {
                return ProcessOutput(exitCode: 0, standardOutput: "Successfully added marketplace: team (github)")
            }
            return ProcessOutput(exitCode: 0, standardOutput: #"{"command":"install","outcome":"ok","message":"ok"}"#)
        }, home: home.home, queue: PluginWriteQueue())
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()), cli: cli)
        let plugin = PluginID(name: "lontano", marketplace: "team")

        let result = try await catalog.fix(with: .installForProject(plugin, marketplaceSource: "azienda/team"))

        #expect(result.succeeded)
        #expect(calls.withLock { $0 }.filter { !$0.contains("list") } == [
            ["plugin", "marketplace", "add", "--scope", "user", "--", "azienda/team"],
            ["plugin", "install", "lontano@team", "--scope", "project", "--json"],
        ])
    }

    @Test func aFailedFirstCommandStopsTheRest() async throws {
        let home = try PluginHome()
        let calls = Mutex(0)
        let cli = PluginCLI(run: { _, _, _ in
            calls.withLock { $0 += 1 }
            return ProcessOutput(exitCode: 1, standardOutput: "✘ Failed to add marketplace: not found")
        }, home: home.home, queue: PluginWriteQueue())
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()), cli: cli)

        let result = try await catalog.fix(with: .installForProject(Self.formatter, marketplaceSource: "a/b"))

        #expect(!result.succeeded)
        #expect(result.message == "Failed to add marketplace: not found")
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func theWindowOpensOnDaSistemareWithTheErrorsOfASessione() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "formattatore", "source": "./plugins/formattatore"]])
        try home.install(["formattatore@ufficiale": [home.installation()]])
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()), configuration: { _ in
            ClaudeConfiguration(skills: [], plugins: [],
                                pluginErrors: [.init(plugin: "formattatore@ufficiale", message: "hook failed", type: "hook-load-failed")],
                                mcpServers: [], instructions: [])
        })
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot?.problems.isEmpty == false }

        let snapshot = try #require(catalog.snapshot)
        #expect(PluginSidebarItem.initialSelection(in: snapshot) == .toFix)
        #expect(catalog.entries(in: .toFix, matching: "").first?.entries.map(\.id) == [Self.formatter])
    }
}
