import Foundation
import Synchronization
import Testing
@testable import Bubo

/// Adding and removing Marketplaces: arguments, the text `claude` prints instead of JSON, the check with
/// `marketplace list --json`, the scopes that declare one and the plugins its removal takes. A fake `claude` and a
/// temporary home: nothing touches `~/.claude`.
struct MarketplaceTests {
    @Test func addAndRemoveNameTheirScopeAndEndOptionsBeforeTheSource() {
        #expect(PluginCommand.addMarketplace(source: "--claudeai", scope: .user).arguments
            == ["plugin", "marketplace", "add", "--scope", "user", "--", "--claudeai"])
        #expect(PluginCommand.removeMarketplace(name: "prova", scope: .project).arguments
            == ["plugin", "marketplace", "remove", "--scope", "project", "--", "prova"])
        #expect(PluginCommand.removeMarketplace(name: "prova", scope: nil).arguments
            == ["plugin", "marketplace", "remove", "--", "prova"])
        #expect(PluginCommand.addMarketplace(source: "a/b", scope: .user).timeout == .seconds(120))
        #expect(PluginCommand.removeMarketplace(name: "prova", scope: nil).plugin == nil)
    }

    @Test(arguments: [
        // Recorded with CLI 2.1.287 and GIT_TERMINAL_PROMPT=0: SSH for owner/repo, HTTPS for a git URL.
        "Adding marketplace…✘ Failed to add marketplace: Failed to clone marketplace repository: SSH authentication failed. Please ensure your SSH keys are configured for GitHub, or use an HTTPS URL instead.\n\nOriginal error: Cloning into '/x'...\ngit@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.",
        "Adding marketplace…✘ Failed to add marketplace: Failed to clone marketplace repository: Cloning into '/x'...\nfatal: unable to get password from user",
    ])
    func aPrivateRepositoryWithoutCredentialsSaysSo(_ error: String) {
        let result = PluginCommandResult(marketplaceOutput: ProcessOutput(exitCode: 1, standardOutput: "", standardError: error),
                                         listed: nil)
        #expect(!result.succeeded)
        #expect(result.isAccessDenied)
    }

    @Test func anotherFailureKeepsTheWordsOfClaude() {
        let output = ProcessOutput(exitCode: 1, standardOutput: "",
                                   standardError: "✘ Invalid marketplace source format. Try: owner/repo, https://..., or ./path\n")
        let result = PluginCommandResult(marketplaceOutput: output, listed: nil)
        #expect(!result.succeeded)
        #expect(!result.isAccessDenied)
        #expect(result.message == "Invalid marketplace source format. Try: owner/repo, https://..., or ./path")
    }

    @Test func theListDecidesWhetherItWorked() {
        let added = ProcessOutput(exitCode: 0, standardOutput: "Adding marketplace…✔ Successfully added marketplace: prova (declared in user settings)\n")
        #expect(PluginCommandResult(marketplaceOutput: added, listed: ["prova"]).succeeded)
        #expect(!PluginCommandResult(marketplaceOutput: added, listed: ["altro"]).succeeded)
        let again = ProcessOutput(exitCode: 0, standardOutput: "Adding marketplace…✔ Marketplace 'prova' already on disk — declared in user settings\n")
        #expect(PluginCommandResult(marketplaceOutput: again, listed: ["prova"]).succeeded)

        let removed = ProcessOutput(exitCode: 0, standardOutput: "✔ Successfully removed marketplace: prova\n")
        #expect(PluginCommandResult(marketplaceOutput: removed, removing: "prova", listed: []).succeeded)
        #expect(!PluginCommandResult(marketplaceOutput: removed, removing: "prova", listed: ["prova"]).succeeded)
        // Nothing to compare: the exit code alone.
        #expect(PluginCommandResult(marketplaceOutput: removed, removing: "prova", listed: nil).succeeded)
    }

    @Test func theCLIAsksTheListAfterAnAddThatEnded() async throws {
        let calls = Mutex<[[String]]>([])
        let cli = PluginCLI(run: { arguments, _ in
            calls.withLock { $0.append(arguments) }
            if arguments.contains("list") {
                return ProcessOutput(exitCode: 0, standardOutput: #"[{"name":"prova","source":"github","repo":"a/prova"}]"#)
            }
            return ProcessOutput(exitCode: 0, standardOutput: "✔ Successfully added marketplace: prova (declared in user settings)")
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
        let result = try await cli.perform(.addMarketplace(source: "a/prova", scope: .user), project: nil)
        #expect(result.succeeded)
        #expect(calls.withLock { $0 }.last == ["plugin", "marketplace", "list", "--json"])

        let scoped = try await cli.perform(.removeMarketplace(name: "prova", scope: .user), project: nil)
        #expect(scoped.succeeded)
        #expect(calls.withLock { $0 }.last?.contains("remove") == true)
    }

    @Test func removingTheLastDeclarationRemovesEverywhere() {
        let both = Marketplace(name: "prova", installLocation: URL(filePath: "/x"), declaredScopes: [.user, .project])
        #expect(both.removalScope(.user) == .user)
        #expect(both.removalScope(nil) == nil)
        let one = Marketplace(name: "prova", installLocation: URL(filePath: "/x"), declaredScopes: [.user])
        #expect(one.removalScope(.user) == nil)
        let undeclared = Marketplace(name: "prova", installLocation: URL(filePath: "/x"))
        #expect(undeclared.removalScope(.user) == nil)
        #expect(!Marketplace(name: "claudeai", installLocation: nil).isRemovable)
    }

    @Test func theSnapshotKnowsTheDeclaringScopesAndEveryPluginTheRemovalTakes() async throws {
        let home = try PluginHome()
        try home.addMarketplace("prova", plugins: [["name": "uno", "source": "./uno"], ["name": "due", "source": "./due"]])
        try home.write(["extraKnownMarketplaces": ["prova": ["source": ["source": "github", "repo": "esempio/prova"]]]],
                       at: home.folders.userSettings.path)
        try home.write(["extraKnownMarketplaces": ["prova": ["source": ["source": "github", "repo": "esempio/prova"]]]],
                       at: home.folders.projectSettings(of: home.project).local.path)
        // Installed in another Progetto too: not shown here, but uninstalled with the Marketplace.
        let elsewhere = home.home.appending(path: "altro", directoryHint: .isDirectory)
        try home.install(["uno@prova": [home.installation(scope: "local", project: elsewhere)],
                          "due@prova": [home.installation()],
                          "tre@altro": [home.installation()]])

        let snapshot = await PluginSnapshot.read(from: home.folders, project: home.project)
        let marketplace = try #require(snapshot.marketplace(named: "prova"))
        #expect(marketplace.declaredScopes == [.user, .local])
        #expect(snapshot.pluginsRemoved(with: marketplace) == [PluginID(name: "due", marketplace: "prova"),
                                                               PluginID(name: "uno", marketplace: "prova")])
        #expect(snapshot.plugins.first { $0.id.name == "uno" }?.isInstalled == false)
    }
}
