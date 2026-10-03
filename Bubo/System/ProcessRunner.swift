import Foundation

/// Runs an executable to completion and collects its output.
///
/// Injected so tests can replace real processes with fixtures.
nonisolated struct ProcessRunner: Sendable {
    /// Runs `executable` with `arguments` and returns its output once it exits.
    ///
    /// Cancelling the calling task terminates the process.
    var run: @Sendable (_ executable: URL, _ arguments: [String]) async throws -> ProcessOutput
}

nonisolated extension ProcessRunner {
    /// Runs real processes with `Process`, standard input closed.
    static let live = ProcessRunner { executable, arguments in
        try await runProcess(executable, arguments: arguments)
    }

    /// Runs real processes with `Process` and exactly `environment`, standard input closed.
    static func live(environment: [String: String]) -> ProcessRunner {
        ProcessRunner { executable, arguments in
            try await runProcess(executable, arguments: arguments, environment: environment)
        }
    }

    /// Runs real processes with `Process`, with `environment` instead of Bubo's own when given; standard input gets
    /// `input`, then is closed.
    static func live(environment: [String: String]?, input: Data) -> ProcessRunner {
        ProcessRunner { executable, arguments in
            try await runProcess(executable, arguments: arguments, environment: environment, input: input)
        }
    }

    /// Runs processes disclaimed (ADR 0005) with exactly `environment`, in `folder` when given; standard input gets
    /// `input`, then is closed.
    ///
    /// Standard error goes to Bubo's own and is not collected, or, when `mergingErrors`, into the standard output,
    /// for a command that tells why it failed only there. `input` is for what must never be an argument, such as a
    /// secret: `ps` shows the arguments to every user of the Mac.
    static func disclaimed(environment: [String: String], in folder: URL? = nil, mergingErrors: Bool = false,
                           input: Data? = nil) -> ProcessRunner {
        ProcessRunner { executable, arguments in
            try await runDisclaimed(executable, arguments: arguments, environment: environment, in: folder,
                                    mergingErrors: mergingErrors, input: input)
        }
    }
}

@concurrent
private func runProcess(_ executable: URL, arguments: [String],
                        environment: [String: String]? = nil, input: Data? = nil) async throws -> ProcessOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if let environment { process.environment = environment }
    let standardInput = input.map { _ in Pipe() }
    process.standardInput = standardInput ?? FileHandle.nullDevice
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    let (exits, exit) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { finished in
        exit.yield(finished.terminationStatus)
        exit.finish()
    }
    try process.run()
    let pid = process.processIdentifier
    if let input, let writer = standardInput?.fileHandleForWriting {
        // Written apart from the reading, so a child that answers before it read everything never blocks on a
        // full pipe; a child that exited early gives an error, never a SIGPIPE.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        Thread.detachNewThread {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
    }
    return try await withTaskCancellationHandler {
        async let standardOutput = readText(from: output.fileHandleForReading)
        async let standardError = readText(from: error.fileHandleForReading)
        var exitCode: Int32 = -1
        for await code in exits { exitCode = code }
        return ProcessOutput(exitCode: exitCode, standardOutput: try await standardOutput, standardError: try await standardError)
    } onCancel: {
        kill(pid, SIGKILL) // an interactive shell ignores SIGTERM
    }
}

@concurrent
private func runDisclaimed(_ executable: URL, arguments: [String], environment: [String: String],
                           in folder: URL?, mergingErrors: Bool, input: Data?) async throws -> ProcessOutput {
    let process = try ProcessSpawner.spawn(executable, arguments: arguments, environment: environment, in: folder,
                                           mergingErrors: mergingErrors)
    // A few hundred bytes at most: they fit in the pipe before the child reads them.
    // A child that already exited gives an error, never a SIGPIPE.
    if let input {
        _ = fcntl(process.input.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try process.input.write(contentsOf: input)
        } catch {
            kill(process.pid, SIGKILL)
            _ = await ProcessSpawner.waitForExit(of: process.pid)
            throw error
        }
    }
    try process.input.close()
    return try await withTaskCancellationHandler {
        let standardOutput = try await readText(from: process.output)
        let exitCode = await ProcessSpawner.waitForExit(of: process.pid)
        return ProcessOutput(exitCode: exitCode, standardOutput: standardOutput)
    } onCancel: {
        kill(process.pid, SIGKILL) // an interactive shell ignores SIGTERM
    }
}

/// Everything `handle` gives until end of file, as UTF-8.
///
/// Read in chunks as they arrive, never with `bytes`: that stalls while the other pipe stays open and silent, and
/// a child that fills one pipe then waits forever, as `git diff` does past 64 KB.
private func readText(from handle: FileHandle) async throws -> String {
    let (chunks, continuation) = AsyncStream.makeStream(of: Data.self)
    handle.readabilityHandler = { handle in
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            continuation.finish()
        } else {
            continuation.yield(chunk)
        }
    }
    var data = Data()
    for await chunk in chunks { data.append(chunk) }
    return String(decoding: data, as: UTF8.self)
}
