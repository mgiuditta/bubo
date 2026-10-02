import Foundation
import os

/// Runs the `claude plugin …` commands that change the plugins (spec 20, Scrittura).
///
/// `claude` by absolute path and disclaimed (ADR 0005), always in the main checkout of the Progetto, never in a
/// worktree (anthropics/claude-code#85278), one command at a time, each with a time limit and cancellable.
nonisolated struct PluginCLI: Sendable {
    /// Runs `claude` with the arguments in the folder and returns its output.
    var run: @Sendable (_ arguments: [String], _ folder: URL) async throws -> ProcessOutput
    /// The folder of the commands without a Progetto.
    var home: URL
    /// Where the commands wait their turn.
    var queue = PluginWriteQueue.shared
    /// How long each command may take.
    var timeout: @Sendable (PluginCommand) -> Duration = { $0.timeout }

    /// The user's `claude`, found by `locator`, with the environment of the plugin listing: git never asks for a
    /// password, so a private repository fails at once instead of hanging.
    static func live(locator: ClaudeLocator = ClaudeLocator(),
                     environment: [String: String] = PluginListing.environment()) -> PluginCLI {
        PluginCLI(run: { arguments, folder in
            guard let claude = await locator.executableURL() else { throw PluginCLIError.claudeMissing }
            return try await ProcessRunner.disclaimed(environment: environment, in: folder).run(claude, arguments)
        }, home: environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) } ?? .homeDirectory)
    }

    /// The folder the commands for `project` run in: its main checkout, or the home without a Progetto.
    func workingFolder(for project: URL?) -> URL {
        project.map { URL(filePath: TrustGate.root(of: $0), directoryHint: .isDirectory) } ?? home
    }

    /// Runs `command` for `project`, after the commands queued before it.
    ///
    /// - Returns: How it ended; a refusal of the CLI is a result, not an error.
    /// - Throws: `PluginCLIError` when `claude` is missing, takes too long or prints no result;
    ///   `CancellationError` when the task is cancelled.
    func perform(_ command: PluginCommand, project: URL?) async throws -> PluginCommandResult {
        let folder = workingFolder(for: project)
        let run = run
        let timeout = timeout(command)
        return try await queue.enqueue {
            let output = try await withThrowingTaskGroup { group in
                group.addTask { try await run(command.arguments, folder) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw PluginCLIError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            if case .prune = command {
                return PluginCommandResult(succeeded: output.exitCode == 0)
            }
            guard let result = PluginCommandResult(output: output.standardOutput) else {
                Logger.plugins.error("claude plugin \(command.arguments[1], privacy: .public) without a result, exit \(output.exitCode)")
                throw PluginCLIError.failed(exitCode: output.exitCode)
            }
            return result
        }
    }
}

/// Why a `claude plugin …` command gave no result.
nonisolated enum PluginCLIError: Error, Equatable {
    case claudeMissing
    case timedOut
    /// It ended without the JSON line, such as for a wrong argument.
    case failed(exitCode: Int32)
}

nonisolated extension PluginCLIError {
    /// What the sheets say.
    var message: LocalizedStringResource {
        switch self {
        case .claudeMissing: "Non trovo claude su questo Mac."
        case .timedOut: "claude non ha risposto in tempo: il comando è stato fermato."
        case let .failed(exitCode): "claude si è fermato senza dire com'è andata (codice \(exitCode))."
        }
    }
}
