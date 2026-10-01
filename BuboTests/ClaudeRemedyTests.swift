import Foundation
import Testing
@testable import Bubo

/// When `claude` is not ready (spec 26): the commands typed in the Terminal, the folders FSEvents watches, and the
/// whole recovery against a fake `claude` in a home folder of the tests. No real `claude` ever runs.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClaudeRemedyTests {
    let home: URL

    init() throws {
        // FSEvents reports real paths: the temporary folder is under /private.
        let folder = FileManager.default.temporaryDirectory.appending(path: "ClaudeRemedyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let real = try #require(realpath(folder.path, nil))
        defer { free(real) }
        home = URL(filePath: String(cString: real), directoryHint: .isDirectory)
    }

    /// A locator that sees only the `claude` of `home`, never one installed on this Mac.
    func locator(runner: ProcessRunner = .live(environment: ["PATH": "/usr/bin:/bin"]),
                 shell: URL = URL(filePath: "/usr/bin/false")) -> ClaudeLocator {
        let home = home
        return ClaudeLocator(home: home, isExecutable: { url in
            url.path.hasPrefix(home.path + "/") && FileManager.default.isExecutableFile(atPath: url.path)
        }, runner: runner, shell: shell)
    }

    /// A watcher of `home` alone.
    func watcher() -> InstallWatcher {
        let home = home
        return InstallWatcher(locator: locator(), folderExists: { url in
            url.path.hasPrefix(home.path) && FileManager.default.fileExists(atPath: url.path)
        }, latency: 0.1)
    }

    // MARK: Commands

    @Test func theLoginNamesTheClaudeBuboFound() {
        #expect(RemedyCommand.login(claude: URL(filePath: "/Users/ada/.local/bin/claude"))
            == "/Users/ada/.local/bin/claude auth login")
        #expect(RemedyCommand.login(claude: URL(filePath: "/Users/Ada Rossi/.local/bin/claude"))
            == "'/Users/Ada Rossi/.local/bin/claude' auth login")
    }

    @Test func aNativeClaudeUpdatesItself() {
        let claude = URL(filePath: "/Users/ada/.local/bin/claude")
        let installation = URL(filePath: "/Users/ada/.local/share/claude/versions/2.0.77")
        #expect(RemedyCommand.update(claude: claude, installation: installation) == "/Users/ada/.local/bin/claude update")
    }

    @Test(arguments: [
        ("/opt/homebrew/Caskroom/claude-code/2.0.77/claude", "/opt/homebrew/bin/brew upgrade claude-code"),
        ("/opt/homebrew/Caskroom/claude-code@latest/2.0.77/claude", "/opt/homebrew/bin/brew upgrade claude-code@latest"),
        ("/usr/local/Caskroom/claude-code/2.0.77/claude", "/usr/local/bin/brew upgrade claude-code"),
    ])
    func aHomebrewClaudeIsUpgradedWithItsCask(installation: String, command: String) {
        let claude = URL(filePath: "/opt/homebrew/bin/claude")
        #expect(RemedyCommand.update(claude: claude, installation: URL(filePath: installation)) == command)
    }

    // MARK: Watched folders

    @Test func theHomeFolderCoversEveryInstallationUnderItAndMissingSystemFoldersAreNotWatched() {
        let ada = URL(filePath: "/Users/ada")
        let existing: Set<String> = ["/Users/ada", "/Users/ada/.local", "/opt/homebrew/bin"]
        let watcher = InstallWatcher(locator: ClaudeLocator(home: ada), folderExists: { existing.contains($0.path) })

        #expect(watcher.roots == ["/Users/ada", "/opt/homebrew/bin"])
        #expect(watcher.watchedFiles.contains("/Users/ada/.claude.json"))
        #expect(watcher.watchedFiles.contains("/Users/ada/.local/bin/claude"))
    }

    @Test func onlyTheWatchedFilesMatter() {
        let files: Set<String> = ["/Users/ada/.claude.json"]
        #expect(InstallWatcher.matters(FileEventBatch(paths: ["/Users/ada/.claude.json"], needsRescan: false, latestID: 1),
                                       files: files))
        #expect(!InstallWatcher.matters(FileEventBatch(paths: ["/Users/ada/.zsh_history"], needsRescan: false, latestID: 1),
                                        files: files))
        #expect(InstallWatcher.matters(FileEventBatch(paths: [], needsRescan: true, latestID: 1), files: files))
    }

    // MARK: Recovery with a fake claude

    /// A `claude` that answers `--version` with `version` and `auth status` as signed in or not.
    func installClaude(at folder: String = ".local/bin", version: String, signedIn: Bool) throws {
        let bin = home.appending(path: folder)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let status = signedIn
            ? #"echo '{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "max"}'; exit 0"#
            : #"echo '{"loggedIn": false, "authMethod": "none"}'; exit 1"#
        let script = """
            #!/bin/sh
            case "$1" in
              --version) echo "\(version) (Claude Code)" ;;
              auth) \(status) ;;
              *) exit 2 ;;
            esac

            """
        let staged = home.appending(path: "claude-\(UUID().uuidString)")
        try Data(script.utf8).write(to: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        // Replaced in one step, as an installer's link: never a half-written `claude`.
        _ = try FileManager.default.replaceItemAt(bin.appending(path: "claude"), withItemAt: staged)
    }

    /// The detection Bubo runs, on `home`, with a login shell that has `bin` of `home` alone on its `PATH`.
    func detect() async -> ClaudeReadiness {
        let shell = home.appending(path: "login-shell")
        if !FileManager.default.fileExists(atPath: shell.path) {
            let script = "#!/bin/sh\nPATH='\(home.appending(path: "bin").path)'\neval \"$4\"\n"
            try? Data(script.utf8).write(to: shell)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        }
        return await ClaudeReadiness.detect(locator: locator(shell: shell),
                                            runner: .live(environment: ["PATH": "/usr/bin:/bin"]))
    }

    @Test func eachStateOfAFakeClaudeIsDetected() async throws {
        #expect(await detect() == .missing)
        try installClaude(version: "2.0.77", signedIn: true)
        #expect(await detect() == .outdated(version: "2.0.77"))
        try installClaude(version: "2.1.286", signedIn: false)
        #expect(await detect() == .signedOut(version: "2.1.286"))
        try installClaude(version: "2.1.286", signedIn: true)
        #expect(await detect() == .ready(version: "2.1.286", method: "Max"))
    }

    @Test func aClaudeOnlyOnTheLoginPathIsFound() async throws {
        try installClaude(at: "bin", version: "2.1.286", signedIn: true)
        #expect(await detect() == .ready(version: "2.1.286", method: "Max"))
    }

    @Test func theQuestionStartsWithinTwoSecondsOfTheInstallationWithoutPolling() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ClaudeRemedyTests-\(UUID().uuidString)"))
        var started: [String] = []
        let flow = OnboardingFlow(hasSessions: false, defaults: defaults, detect: { await detect() }) { question, _ in
            started.append(question)
            return UUID()
        }
        flow.choose(home)
        flow.draft = "Trova i TODO più vecchi"
        flow.send()
        await flow.detectClaude()
        #expect(flow.readiness == .missing)

        let changes = watcher().changes()
        // FSEvents needs a moment to start watching before the change it should see.
        try await Task.sleep(for: .milliseconds(300))
        let installed = ContinuousClock.now
        try installClaude(version: "2.1.286", signedIn: true)
        for await _ in changes {
            await flow.recheck()
            if !flow.needsRemedy { break }
        }

        #expect(started == ["Trova i TODO più vecchi"])
        #expect(ContinuousClock.now - installed < .seconds(2))
    }

    @Test func aLoginInAnotherTerminalIsSeenOnItsOwn() async throws {
        try installClaude(version: "2.1.286", signedIn: false)
        let changes = watcher().changes()
        try await Task.sleep(for: .milliseconds(300))

        // `claude auth login` replaces `~/.claude.json` whole.
        try Data(#"{"oauthAccount": {}}"#.utf8).write(to: home.appending(path: ".claude.json"), options: .atomic)

        var events = changes.makeAsyncIterator()
        #expect(await events.next() != nil)
    }
}
