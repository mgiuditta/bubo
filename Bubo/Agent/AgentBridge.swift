import Foundation
import os

/// Errors from a conversation through the agent bridge.
enum AgentBridgeError: Error, Equatable {
    /// The bridge could not start.
    case spawnFailed(errno: Int32)
    /// The bridge exited with this status before the answer was complete.
    case bridgeExited(status: Int32)
    /// The bridge or `claude` reported this failure.
    case failed(message: String)
    /// The bridge speaks another protocol version.
    case unsupportedVersion(Int)
}

/// Talks to the agent bridge, a child process that drives `claude` through the Agent SDK.
///
/// The bridge starts on the first request, disclaimed (ADR 0005), and serves every
/// conversation until it exits; the next request starts a new one.
final class AgentBridge {
    /// Creates a bridge that runs `executable` with `environment`.
    init(executable: URL, arguments: [String] = [], environment: [String: String], trustGate: TrustGate = TrustGate()) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.trustGate = trustGate
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let trustGate: TrustGate
    private var process: SpawnedProcess?
    private var answers: [String: AsyncThrowingStream<String, any Error>.Continuation] = [:]

    /// Asks `claude` to answer `prompt` in `directory`, streaming the answer as it arrives.
    ///
    /// `claude` loads the settings of `directory` only if it is trusted (`TrustGate`), never by the SDK's default.
    ///
    /// Cancelling the iteration interrupts the conversation.
    func ask(_ prompt: String, in directory: URL) -> AsyncThrowingStream<String, any Error> {
        let id = UUID().uuidString
        let (answer, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor in self?.cancel(id) }
        }
        do {
            let process = try runningProcess()
            answers[id] = continuation
            let command = BridgeCommand.ask(id: id, prompt: prompt, directory: directory,
                                            settingSources: trustGate.settingSources(for: directory))
            try process.input.write(contentsOf: command.line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            answers[id] = nil
            continuation.finish(throwing: error)
        }
        return answer
    }

    private func cancel(_ id: String) {
        guard answers.removeValue(forKey: id) != nil, let process else { return }
        try? process.input.write(contentsOf: BridgeCommand.cancel(id: id).line())
    }

    private func runningProcess() throws -> SpawnedProcess {
        if let process { return process }
        let process = try ProcessSpawner.spawn(executable, arguments: arguments, environment: environment)
        self.process = process
        Logger.agent.notice("Bridge started, pid \(process.pid), disclaimed: \(process.isDisclaimed)")
        Task { await read(process) }
        return process
    }

    private func read(_ process: SpawnedProcess) async {
        let decoder = JSONDecoder()
        for await line in process.output.lines where !line.isEmpty {
            do {
                handle(try decoder.decode(BridgeEvent.self, from: Data(line.utf8)))
            } catch {
                Logger.agent.error("Unreadable bridge line: \(error)")
            }
        }
        let status = await ProcessSpawner.waitForExit(of: process.pid)
        Logger.agent.notice("Bridge exited with status \(status)")
        self.process = nil
        finishAll(throwing: .bridgeExited(status: status))
    }

    private func handle(_ event: BridgeEvent) {
        switch event {
        case .ready:
            break
        case let .text(id, text):
            answers[id]?.yield(text)
        case let .done(id):
            answers.removeValue(forKey: id)?.finish()
        case let .error(id?, message):
            answers.removeValue(forKey: id)?.finish(throwing: AgentBridgeError.failed(message: message))
        case let .error(nil, message):
            finishAll(throwing: .failed(message: message))
        case let .unsupportedVersion(version):
            finishAll(throwing: .unsupportedVersion(version))
        }
    }

    private func finishAll(throwing error: AgentBridgeError) {
        let pending = answers
        answers = [:]
        pending.values.forEach { $0.finish(throwing: error) }
    }
}
