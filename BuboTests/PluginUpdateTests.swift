import Foundation
import Synchronization
import Testing
@testable import Bubo

/// The updates of every Marketplace: the version Claude Code would install, the daily check, Aggiorna in one click
/// or with a confirmation, the version the author did not change, and the code an update of Claude Code brought.
/// A fake `claude` and a fake git: no network, nothing touches `~/.claude`.
@MainActor
struct PluginUpdateTests {
    nonisolated static let plugin = PluginID(name: "revisore", marketplace: "terzi")
    nonisolated static let old = String(repeating: "a", count: 40)
    nonisolated static let new = String(repeating: "b", count: 40)

    /// One row of the version table.
    struct VersionCase: Sendable, CustomTestStringConvertible {
        let name: String
        let source: PluginSource
        var entryVersion: String?
        var sha: String?
        var manifestVersion: String?
        var tip: String?
        var installedVersion: String?
        var installedCommit: String?
        var scopes: [PluginScope] = [.user]
        var dismissed: String?
        let expected: PluginUpdate.Certainty?

        var testDescription: String { name }
    }

    nonisolated static let versionTable: [VersionCase] = [
        VersionCase(name: "relative, plugin.json newer", source: .relative(path: "./p"), entryVersion: "1.0.0",
                    manifestVersion: "1.1.0", installedVersion: "1.0.0", expected: .certain),
        VersionCase(name: "relative, plugin.json first, entry version ignored", source: .relative(path: "./p"),
                    entryVersion: "2.0.0", manifestVersion: "1.0.0", installedVersion: "1.0.0", expected: nil),
        VersionCase(name: "relative, entry version", source: .relative(path: "./p"), entryVersion: "2.0.0",
                    installedVersion: "1.0.0", expected: .certain),
        VersionCase(name: "relative, no version, clone moved", source: .relative(path: "./p"), tip: new,
                    installedVersion: String(old.prefix(12)), installedCommit: old, expected: .certain),
        VersionCase(name: "relative, no version, same commit", source: .relative(path: "./p"), tip: old,
                    installedVersion: String(old.prefix(12)), installedCommit: old, expected: nil),
        VersionCase(name: "github, entry version newer", source: .github(repo: "a/b"), entryVersion: "3.0.0",
                    installedVersion: "2.0.0", expected: .certain),
        VersionCase(name: "github, same entry version", source: .github(repo: "a/b"), entryVersion: "2.0.0",
                    installedVersion: "2.0.0", expected: nil),
        VersionCase(name: "url, sha moved", source: .url("https://example.com/r.git"), sha: new,
                    installedVersion: String(old.prefix(12)), installedCommit: old, expected: .possible),
        VersionCase(name: "url, sha installed", source: .url("https://example.com/r.git"), sha: old,
                    installedVersion: String(old.prefix(12)), expected: nil),
        VersionCase(name: "git-subdir, ls-remote moved", source: .gitSubdirectory(url: "https://example.com/r.git", path: "p"),
                    tip: new, installedVersion: String(old.prefix(12)), expected: .possible),
        VersionCase(name: "github, no sha, no ls-remote", source: .github(repo: "a/b"),
                    installedVersion: String(old.prefix(12)), expected: nil),
        VersionCase(name: "npm: unknown", source: .npm(package: "p"), entryVersion: "9.0.0", installedVersion: "unknown",
                    expected: nil),
        VersionCase(name: "command: hash of the output", source: .command("echo /tmp/p"), entryVersion: "9.0.0",
                    installedVersion: "1.0.0", expected: nil),
        VersionCase(name: "archive", source: .archive("https://example.com/p.zip"), entryVersion: "9.0.0",
                    installedVersion: "1.0.0", expected: nil),
        VersionCase(name: "not installed", source: .github(repo: "a/b"), entryVersion: "3.0.0", scopes: [], expected: nil),
        VersionCase(name: "managed only", source: .github(repo: "a/b"), entryVersion: "3.0.0", installedVersion: "2.0.0",
                    scopes: [.managed], expected: nil),
        VersionCase(name: "installed without version", source: .github(repo: "a/b"), entryVersion: "3.0.0", expected: nil),
        VersionCase(name: "version the author did not change", source: .github(repo: "a/b"), entryVersion: "3.0.0",
                    installedVersion: "2.0.0", dismissed: "3.0.0", expected: nil),
        VersionCase(name: "a newer one after the dismissed", source: .github(repo: "a/b"), entryVersion: "3.1.0",
                    installedVersion: "2.0.0", dismissed: "3.0.0", expected: .certain),
    ]

    @Test(arguments: versionTable)
    func theVersionTable(_ row: VersionCase) {
        let entry = PluginEntry(id: Self.plugin, source: row.source, version: row.entryVersion,
                                revision: PluginRevision(sha: row.sha),
                                installations: row.scopes.map { scope in
                                    PluginInstallation(scope: scope, projectPath: nil, installPath: nil,
                                                       version: row.installedVersion, gitCommitSha: row.installedCommit,
                                                       isEnabled: true)
                                })
        let update = PluginUpdate.update(for: entry, manifestVersion: row.manifestVersion, tip: row.tip,
                                         dismissed: row.dismissed)
        #expect(update?.certainty == row.expected)
    }

    @Test func theMostSpecificScopeIsUpdatedAndTheCommandNeverSaysYes() throws {
        let entry = PluginEntry(id: Self.plugin, source: .github(repo: "a/b"), version: "2.0.0", installations: [
            PluginInstallation(scope: .user, projectPath: nil, installPath: nil, version: "1.0.0", gitCommitSha: nil, isEnabled: true),
            PluginInstallation(scope: .local, projectPath: nil, installPath: nil, version: "1.0.0", gitCommitSha: nil, isEnabled: true),
        ])
        let update = try #require(PluginUpdate.update(for: entry))
        #expect(update.scope == .local)
        #expect(PluginCommand.update(Self.plugin, scope: .local).arguments
            == ["plugin", "update", "revisore@terzi", "--scope", "local", "--json"])
        let shown = PluginShownCommand(command: "echo /tmp/p", sha256: "afb8")
        #expect(PluginCommand.update(Self.plugin, scope: .user, accepting: shown).arguments.suffix(2) == ["--accept-command", "afb8"])
        #expect(PluginCommand.updateMarketplaces.arguments == ["plugin", "marketplace", "update"])
        #expect(!PluginCommand.updateMarketplaces.arguments.contains("-y"))
        #expect(PluginUpdate(plugin: Self.plugin, scope: .user, version: Self.new, certainty: .possible).displayVersion == "bbbbbbb")
    }

    @Test func onlySafeGitURLsReachLsRemote() {
        func remote(_ source: PluginSource, ref: String? = nil) -> PluginUpdateChecker.Remote? {
            PluginUpdateChecker.remote(of: PluginEntry(id: Self.plugin, source: source, revision: PluginRevision(ref: ref)))
        }
        #expect(remote(.github(repo: "a/b"))?.url == "https://github.com/a/b.git")
        #expect(remote(.url("git@github.com:a/b.git"), ref: "v2")?.key == "git@github.com:a/b.git#v2")
        #expect(remote(.url("--upload-pack=touch /tmp/x")) == nil)
        #expect(remote(.url("ext::sh -c touch% /tmp/x")) == nil)
        #expect(remote(.url("https://example.com/r.git"), ref: "--output=x") == nil)
        #expect(PluginUpdateChecker.commit(inLsRemote: "\(Self.new)\tHEAD\n") == Self.new)
        #expect(PluginUpdateChecker.commit(inLsRemote: "fatal: could not read Username") == nil)
    }

    @Test func theCloneHeadIsReadFromItsFiles() throws {
        let home = try PluginHome()
        try home.write(Data("ref: refs/heads/main\n".utf8), at: "loose/.git/HEAD")
        try home.write(Data("\(Self.new)\n".utf8), at: "loose/.git/refs/heads/main")
        try home.write(Data("ref: refs/heads/main\n".utf8), at: "packed/.git/HEAD")
        try home.write(Data("# pack-refs with: peeled\n\(Self.old) refs/heads/main\n".utf8), at: "packed/.git/packed-refs")
        try home.write(Data("\(Self.old)\n".utf8), at: "detached/.git/HEAD")

        #expect(PluginUpdateChecker.head(ofClone: home.home.appending(path: "loose")) == Self.new)
        #expect(PluginUpdateChecker.head(ofClone: home.home.appending(path: "packed")) == Self.old)
        #expect(PluginUpdateChecker.head(ofClone: home.home.appending(path: "detached")) == Self.old)
        #expect(PluginUpdateChecker.head(ofClone: home.home.appending(path: "nessuno")) == nil)
    }

    @Test func theDailyCheckRunsOnceADayForEveryMarketplace() async throws {
        let home = try PluginHome()
        try home.addMarketplace("terzi", plugins: [
            ["name": "revisore", "source": ["source": "github", "repo": "a/revisore"]],
            ["name": "fissato", "source": ["source": "github", "repo": "a/fissato", "sha": Self.old]],
            ["name": "assente", "source": ["source": "github", "repo": "a/assente"]],
        ])
        try home.install(["revisore@terzi": [home.installation()], "fissato@terzi": [home.installation()]])
        let calls = Mutex<[[String]]>([])
        let asked = Mutex<[String]>([])
        let checker = PluginUpdateChecker(cli: PluginCLI(run: { arguments, _, _ in
            calls.withLock { $0.append(arguments) }
            return ProcessOutput(exitCode: 0, standardOutput: "✔ Successfully updated 1 marketplace(s)")
        }, home: home.home, queue: PluginWriteQueue()), folders: home.folders, store: .inMemory()) { url, _ in
            asked.withLock { $0.append(url) }
            return Self.new
        }
        let now = Date.now
        #expect(await checker.checkIfDue(now: now))
        #expect(calls.withLock { $0 } == [["plugin", "marketplace", "update"]])
        // Only the installed plugin with no version and no sha needs git.
        #expect(asked.withLock { $0 } == ["https://github.com/a/revisore.git"])
        #expect(checker.store.current.tips == ["https://github.com/a/revisore.git#HEAD": Self.new])

        #expect(await !checker.checkIfDue(now: now.addingTimeInterval(23 * 60 * 60)))
        #expect(await checker.checkIfDue(now: now.addingTimeInterval(25 * 60 * 60)))
        #expect(calls.withLock { $0 }.count == 2)
    }

    @Test func everyMarketplaceShowsItsUpdatesInTheWindow() async throws {
        let home = try PluginHome()
        try home.addMarketplace("terzi", plugins: [["name": "revisore", "version": "2.0.0", "source": ["source": "github", "repo": "a/r"]]])
        try home.addMarketplace("altro", plugins: [["name": "fermo", "version": "1.0.0", "source": ["source": "github", "repo": "a/f"]]])
        try home.install(["revisore@terzi": [home.installation()], "fermo@altro": [home.installation()]])
        let catalog = PluginCatalog(folders: home.folders, listing: .never)
        let following = Task { await catalog.follow(project: nil) }
        defer { following.cancel() }
        try await waitForCondition { !catalog.updates.isEmpty }

        #expect(catalog.updates.keys.map(\.description) == ["revisore@terzi"])
        #expect(catalog.updates[Self.plugin]?.version == "2.0.0")
        #expect(catalog.entries(in: .updates, matching: "").first?.entries.map(\.id) == [Self.plugin])
    }

    @Test func aVersionTheAuthorDidNotChangeIsExplainedAndNotOfferedAgain() async throws {
        let home = try PluginHome()
        try home.addMarketplace("terzi", plugins: [["name": "revisore", "version": "2.0.0", "source": ["source": "github", "repo": "a/r"]]])
        try home.install(["revisore@terzi": [home.installation()]])
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()), cli: Self.cli { _ in
            ProcessOutput(exitCode: 0, standardOutput: #"{"command":"update","outcome":"ok","message":"revisore is already at the latest version (1.0.0)."}"#)
        })
        let following = Task { await catalog.follow(project: nil) }
        defer { following.cancel() }
        try await waitForCondition { catalog.updates[Self.plugin] != nil }

        let outcome = try await catalog.apply(try #require(catalog.updates[Self.plugin]))
        #expect(outcome == .unchanged)
        #expect(catalog.updates[Self.plugin] == nil)
        #expect(catalog.updateStore.current.dismissed == ["revisore@terzi": "2.0.0"])
    }

    @Test func anUpdateThatChangesTheVersionIsApplied() async throws {
        let home = try PluginHome()
        try home.addMarketplace("terzi", plugins: [["name": "revisore", "version": "2.0.0", "source": ["source": "github", "repo": "a/r"]]])
        try home.install(["revisore@terzi": [home.installation()]])
        var installation = home.installation()
        installation["version"] = "2.0.0"
        let updated = try JSONSerialization.data(withJSONObject: ["version": 2, "plugins": ["revisore@terzi": [installation]]])
        let file = home.folders.installedPlugins
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()), cli: Self.cli { arguments in
            #expect(arguments.starts(with: ["plugin", "update", "revisore@terzi", "--scope", "user"]))
            try updated.write(to: file)
            return ProcessOutput(exitCode: 0, standardOutput: #"{"command":"update","outcome":"ok","message":""}"#)
        })
        let following = Task { await catalog.follow(project: nil) }
        defer { following.cancel() }
        try await waitForCondition { catalog.updates[Self.plugin] != nil }

        let outcome = try await catalog.apply(try #require(catalog.updates[Self.plugin]))
        #expect(outcome == .updated)
        #expect(catalog.updates.isEmpty)
        #expect(catalog.updateStore.current.dismissed.isEmpty)
    }

    @Test func newCodeOnTheMacNeedsAConfirmationAndUnknownCountsAsNew() {
        let skill = PluginComponent.skill("rivedi")
        let hook = PluginComponent.hook(event: "PreToolUse")
        let remote = PluginComponent.mcpServer(name: "docs", isRemote: true)
        let local = PluginComponent.mcpServer(name: "db", isRemote: false)
        let installed = PluginInventory(components: [skill, hook])

        #expect(PluginUpdateChecker.newExecutables(installed: installed,
                                                   latest: PluginInventory(components: [skill, hook, remote, .command("c")])) == [])
        #expect(PluginUpdateChecker.newExecutables(installed: installed,
                                                   latest: PluginInventory(components: [skill, hook, local])) == [local])
        #expect(PluginUpdateChecker.newExecutables(installed: installed, latest: nil) == nil)
        #expect(PluginUpdateChecker.newExecutables(installed: nil, latest: PluginInventory(components: [hook])) == [hook])
    }

    @Test func codeAnUpdateOfClaudeCodeBroughtGoesToDaSistemareUntilSeen() async throws {
        let home = try PluginHome()
        let folder = home.home.appending(path: "cache/terzi/revisore/1.0.0", directoryHint: .isDirectory)
        try home.write(Data("# Rivedi".utf8), at: folder.appending(path: "skills/rivedi/SKILL.md").path)
        try home.addMarketplace("terzi", plugins: [["name": "revisore", "source": ["source": "github", "repo": "a/r"]]])
        try home.install(["revisore@terzi": [home.installation(path: folder)]])
        try home.enableForUser(["revisore@terzi": true])
        let catalog = PluginCatalog(folders: home.folders, listing: .never)
        let following = Task { await catalog.follow(project: nil) }
        defer { following.cancel() }
        try await waitForCondition { catalog.updateStore.current.seenExecutables["revisore@terzi"] == [] }
        #expect(catalog.snapshot?.problems.isEmpty == true)

        // Claude Code updates the plugin on its own: a hook appears.
        try home.write(["hooks": ["PreToolUse": [["hooks": [["type": "command", "command": "true"]]]]]],
                       at: folder.appending(path: "hooks/hooks.json").path)
        try home.install(["revisore@terzi": [home.installation(path: folder)]])
        try await waitForCondition { catalog.snapshot?.problems.isEmpty == false }
        let problem = try #require(catalog.snapshot?.problems.first)
        #expect(problem == .newExecutableCode(Self.plugin, components: [.hook(event: "PreToolUse")]))
        let snapshot = try #require(catalog.snapshot)
        let entry = snapshot.plugins.first { $0.id == Self.plugin }
        #expect(PluginRemedy(problem: problem, entry: entry, snapshot: snapshot) == .disable(Self.plugin, scope: .user))

        await catalog.acknowledgeNewCode(of: Self.plugin)
        #expect(catalog.snapshot?.problems.isEmpty == true)
        #expect(catalog.updateStore.current.seenExecutables["revisore@terzi"] == ["hook/PreToolUse"])
    }

    @Test func theStateSurvivesARelaunch() throws {
        let home = try PluginHome()
        let file = home.home.appending(path: "Bubo/Aggiornamenti dei plugin.json")
        let store = PluginUpdateStore(file: file)
        store.change { $0.dismissed["revisore@terzi"] = "2.0.0" }
        #expect(store.claimCheck(at: .now, interval: PluginUpdateChecker.interval))
        let again = PluginUpdateStore(file: file)
        #expect(again.current.dismissed == ["revisore@terzi": "2.0.0"])
        #expect(!again.claimCheck(at: .now, interval: PluginUpdateChecker.interval))
    }

    /// A `claude` that answers `plugin update` with `answer`, on its own queue.
    nonisolated static func cli(_ answer: @escaping @Sendable ([String]) throws -> ProcessOutput) -> PluginCLI {
        PluginCLI(run: { arguments, _, _ in try answer(arguments) }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
    }
}
