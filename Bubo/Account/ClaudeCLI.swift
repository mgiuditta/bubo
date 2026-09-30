import Foundation

/// The user's own `claude` CLI, used only for its `auth` commands (ADR 0003).
// ponytail: auth commands run without the ADR 0005 disclaim; they only touch ~/.claude. #66 brings ProcessSpawner.
struct ClaudeCLI: Sendable {
    /// Runs the shell and `claude`.
    var runner = ProcessRunner.live
    /// Whether the Mac is online.
    var isOnline: @Sendable () async -> Bool = { await NetworkStatus.isOnline() }
    /// The user's login shell, whose `PATH` finds `claude` even when Bubo starts from the Finder.
    var shell = URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")

    /// Returns the account state from `claude auth status`.
    func status() async -> AccountState {
        guard let claude = await executableURL() else { return .cliMissing }
        guard await isOnline() else { return .offline }
        do {
            return AccountState(statusOutput: try await runner.run(claude, ["auth", "status", "--json"]))
        } catch {
            return .unknownError(exitCode: -1)
        }
    }

    /// Runs `claude auth login`, which opens the browser, and returns when the login ends.
    ///
    /// - Throws: `ClaudeCLIError`, or `CancellationError` when the task is cancelled.
    func signIn() async throws {
        try await runAuth("login")
    }

    /// Runs `claude auth logout`.
    ///
    /// - Throws: `ClaudeCLIError`.
    func signOut() async throws {
        try await runAuth("logout")
    }

    /// Finds `claude` on the `PATH` of an interactive login shell, as Terminal would.
    func executableURL() async -> URL? {
        let output = try? await withThrowingTaskGroup { group in
            group.addTask { try await runner.run(shell, ["-l", "-i", "-c", "command -v claude"]) }
            // An interactive shell can stall on a prompt from the user's profile.
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next()
        }
        guard let output, output.exitCode == 0,
              let path = output.standardOutput.split(whereSeparator: \.isNewline).last,
              path.hasPrefix("/")
        else { return nil }
        return URL(filePath: String(path))
    }

    private func runAuth(_ command: String) async throws {
        guard let claude = await executableURL() else { throw ClaudeCLIError.cliMissing }
        let output = try await runner.run(claude, ["auth", command])
        try Task.checkCancellation()
        guard output.exitCode == 0 else { throw ClaudeCLIError.failed(exitCode: output.exitCode) }
    }
}
