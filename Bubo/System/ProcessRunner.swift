import Foundation

/// Runs an executable to completion and collects its output.
///
/// Injected so tests can replace real processes with fixtures.
struct ProcessRunner: Sendable {
    /// Runs `executable` with `arguments` and returns its output once it exits.
    ///
    /// Cancelling the calling task terminates the process.
    var run: @Sendable (_ executable: URL, _ arguments: [String]) async throws -> ProcessOutput
}

extension ProcessRunner {
    /// Runs real processes with `Process`, standard input closed.
    static let live = ProcessRunner { executable, arguments in
        try await runProcess(executable, arguments: arguments)
    }
}

@concurrent
private func runProcess(_ executable: URL, arguments: [String]) async throws -> ProcessOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
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

private func readText(from handle: FileHandle) async throws -> String {
    var data = Data()
    for try await byte in handle.bytes { data.append(byte) }
    return String(decoding: data, as: UTF8.self)
}
