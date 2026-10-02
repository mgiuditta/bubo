import Foundation

/// `claude plugin list --json --available`, the only command of the read-only Plugin window: it reads, never writes.
nonisolated struct PluginListing: Sendable {
    /// The arguments of the only command.
    static let arguments = ["plugin", "list", "--json", "--available"]
    /// How long `claude` may take.
    static let timeout = Duration.seconds(60)

    /// Lists the plugins as `claude` sees them.
    ///
    /// - Throws: `PluginListingError`, or `CancellationError` when the task is cancelled.
    var list: @Sendable () async throws -> PluginList

    /// The user's `claude`, found by `locator` and run disclaimed (ADR 0005), with git that never asks for a password.
    static func live(locator: ClaudeLocator = ClaudeLocator(),
                     runner: ProcessRunner = .disclaimed(environment: environment())) -> PluginListing {
        PluginListing {
            guard let claude = await locator.executableURL() else { throw PluginListingError.claudeMissing }
            let output = try await withThrowingTaskGroup { group in
                group.addTask { try await runner.run(claude, arguments) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw PluginListingError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            guard output.exitCode == 0 else { throw PluginListingError.failed(exitCode: output.exitCode) }
            guard let list = PluginList(output: output.standardOutput) else { throw PluginListingError.unreadable }
            return list
        }
    }

    /// The environment of `claude`: the user's basics, the folders where `claude` and git live, no git prompts.
    static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { (ChildEnvironment.copied + ["CLAUDE_CODE_PLUGIN_CACHE_DIR"]).contains($0.key) }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = ""
        return environment
    }
}

/// Why `claude plugin list` gave no list.
nonisolated enum PluginListingError: Error, Equatable {
    case claudeMissing
    case timedOut
    case failed(exitCode: Int32)
    case unreadable
}
