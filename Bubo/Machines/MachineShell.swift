import Foundation

/// Where Bubo runs the commands of a Progetto and reads its files: the Mac, or a Macchina through SSH (spec 23).
///
/// git, the revisione and Fondi go through it, so they work the same on both: on a Macchina nothing of the
/// Progetto is ever read from the Mac's disk.
nonisolated protocol MachineShell: Sendable {
    /// Runs `command`, its first word looked up in the `PATH`, with `environment` on top of the shell's own;
    /// standard input gets `input`, then is closed.
    ///
    /// - Throws: `MachineShellError.unreachable` when the Macchina cannot be reached.
    func run(_ command: [String], environment: [String: String], input: Data?) async throws -> ProcessOutput

    /// The contents of the file at `path`; `nil` when it cannot be read.
    func contents(ofFile path: String) async -> Data?

    /// Whether something is at `path`, following symbolic links.
    func fileExists(atPath path: String) async -> Bool
}

/// Why a command of a ``MachineShell`` did not run.
nonisolated enum MachineShellError: Error, Equatable {
    /// The Macchina did not answer, with what `ssh` wrote on standard error.
    case unreachable(String)
    /// A command the shell needs failed, with what it wrote on standard error.
    case failed(String)
}

nonisolated extension MachineShell {
    /// Runs `command` like ``run(_:environment:input:)``, with nothing on standard input.
    func run(_ command: [String], environment: [String: String] = [:]) async throws -> ProcessOutput {
        try await run(command, environment: environment, input: nil)
    }

    func contents(ofFile path: String) async -> Data? {
        guard let output = try? await run(["cat", "--", path]), output.exitCode == 0 else { return nil }
        return Data(output.standardOutput.utf8)
    }

    func fileExists(atPath path: String) async -> Bool {
        (try? await run(["test", "-e", path]))?.exitCode == 0
    }

    /// Copies the file at `source` to `destination`.
    ///
    /// - Throws: `MachineShellError` when the copy fails.
    func copyFile(atPath source: String, toPath destination: String) async throws {
        let output = try await run(["cp", "--", source, destination])
        guard output.exitCode == 0 else { throw MachineShellError.failed(output.standardError) }
    }

    /// Runs `body` with a new empty folder of the shell's temporary files, removed afterwards.
    ///
    /// - Throws: `MachineShellError` when the folder cannot be made; what `body` throws.
    func withTemporaryFolder<Result>(_ body: (_ folder: String) async throws -> Result) async throws -> Result {
        let made = try await run(["mktemp", "-d"])
        let folder = made.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard made.exitCode == 0, folder.hasPrefix("/") else { throw MachineShellError.failed(made.standardError) }
        do {
            let result = try await body(folder)
            _ = try? await run(["rm", "-rf", "--", folder])
            return result
        } catch {
            _ = try? await run(["rm", "-rf", "--", folder])
            throw error
        }
    }
}

/// The Mac's own shell: commands as child processes of Bubo, files read from its disk.
nonisolated struct LocalShell: MachineShell {
    /// The environment of the commands instead of Bubo's own, when given.
    var environment: [String: String]?

    func run(_ command: [String], environment extra: [String: String], input: Data?) async throws -> ProcessOutput {
        let runner = if let input {
            ProcessRunner.live(environment: environment, input: input)
        } else if let environment {
            ProcessRunner.live(environment: environment)
        } else {
            ProcessRunner.live
        }
        let assignments = extra.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return try await runner.run(URL(filePath: "/usr/bin/env"), assignments + command)
    }

    func contents(ofFile path: String) async -> Data? {
        try? Data(contentsOf: URL(filePath: path))
    }

    func fileExists(atPath path: String) async -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// The shell of a Macchina: every command through `ssh` on its ControlMaster, without a terminal and without
/// ever asking a question, so a connection that needs one fails instead of waiting (spec 23).
nonisolated struct SSHShell: MachineShell {
    /// The Macchina the commands run on.
    let machine: Machine
    /// The folder of the ControlMaster sockets.
    var controlFolder = SSHCommand.controlFolder()
    /// Runs `ssh` with the given arguments and standard input; injected so tests never connect to a host.
    var openSSH: @Sendable (_ arguments: [String], _ input: Data?) async throws -> ProcessOutput = { arguments, input in
        let environment = SSHCommand.environment(from: ProcessInfo.processInfo.environment)
        let runner = input.map { ProcessRunner.live(environment: environment, input: $0) }
            ?? .live(environment: environment)
        return try await runner.run(SSHCommand.executable, arguments)
    }

    /// The exit status of `ssh` itself when the connection fails.
    static let connectionFailure: Int32 = 255

    func run(_ command: [String], environment: [String: String], input: Data?) async throws -> ProcessOutput {
        let line = Self.commandLine(command, environment: environment)
        let output = try await openSSH(SSHCommand.backgroundArguments(running: line, on: machine,
                                                                       controlFolder: controlFolder), input)
        guard output.exitCode != Self.connectionFailure else {
            throw MachineShellError.unreachable(output.standardError)
        }
        return output
    }

    /// The line the host's shell runs for `command` with `environment`: every word in single quotes, so the
    /// host runs exactly those words, whatever spaces, quotes, `$` or other characters they hold.
    static func commandLine(_ command: [String], environment: [String: String]) -> String {
        let assignments = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return (["exec", "env"] + (assignments + command).map(quoted)).joined(separator: " ")
    }

    /// `word` in single quotes for any POSIX shell.
    static func quoted(_ word: String) -> String {
        "'\(word.replacing("'", with: #"'\''"#))'"
    }
}
