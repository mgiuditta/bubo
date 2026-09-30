import Foundation

/// Exit code and output of a finished command.
struct CommandResult: Equatable, Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError = ""
}

/// Errors from running the `claude` CLI.
enum ClaudeCLIError: Error, Equatable {
    /// No `claude` binary in the user's login `PATH` nor in the usual install folders.
    case binaryNotFound
}

/// Runs the user's `claude` CLI. Bubo never reads its credentials (ADR 0003).
struct ClaudeCLI: Sendable {
    /// Runs `claude` with the given arguments and returns when it exits.
    var run: @Sendable (_ arguments: [String]) async throws -> CommandResult

    /// The `claude` found through the user's login shell, so it works when Bubo starts from the Finder.
    static let live = ClaudeCLI { arguments in
        guard let binary = await BinaryLocator.claude() else { throw ClaudeCLIError.binaryNotFound }
        return try await Command.run(binary, arguments: arguments)
    }
}

/// Finds `claude` the way the user's terminal would.
private enum BinaryLocator {
    /// Returns the path of `claude`, or `nil` when it isn't installed.
    @concurrent static func claude() async -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // -i as well as -l: many installers add ~/.local/bin to .zshrc, which only interactive shells read.
        if let result = try? await Command.run(URL(filePath: shell), arguments: ["-ilc", "command -v claude"]),
           result.exitCode == 0,
           let path = result.standardOutput.split(separator: "\n").last(where: { $0.hasPrefix("/") }) {
            return URL(filePath: String(path))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(filePath: $0) }
    }
}

/// Runs a process to completion off the main actor.
enum Command {
    /// Runs `executable` and collects its output once it exits.
    @concurrent static func run(_ executable: URL, arguments: [String]) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // ponytail: reads to EOF before waiting, so a full pipe can't deadlock; stderr read after stdout is fine for short CLI output.
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}
