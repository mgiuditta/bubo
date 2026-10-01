import Foundation

/// The user's own `claude` CLI, used only for its `auth` commands (ADR 0003).
// ponytail: auth commands run without the ADR 0005 disclaim; they only touch ~/.claude. #66 brings ProcessSpawner.
struct ClaudeCLI: Sendable {
    /// Runs `claude`.
    var runner = ProcessRunner.live
    /// Whether the Mac is online.
    var isOnline: @Sendable () async -> Bool = { await NetworkStatus.isOnline() }
    /// Finds `claude` even when Bubo starts from the Finder.
    var locator = ClaudeLocator()

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

    /// The `claude` that `ClaudeLocator` finds.
    func executableURL() async -> URL? {
        await locator.executableURL()
    }

    private func runAuth(_ command: String) async throws {
        guard let claude = await executableURL() else { throw ClaudeCLIError.cliMissing }
        let output = try await runner.run(claude, ["auth", command])
        try Task.checkCancellation()
        guard output.exitCode == 0 else { throw ClaudeCLIError.failed(exitCode: output.exitCode) }
    }
}
