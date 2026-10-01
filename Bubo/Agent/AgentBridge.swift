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
    /// `claude` stopped at a subscription limit.
    case limitReached(Quota.Limit)
    /// The login of `claude` is no longer valid.
    case signInRequired
}

/// Talks to the agent bridge, a child process that drives `claude` through the Agent SDK.
///
/// The bridge starts on the first request, disclaimed (ADR 0005), and serves every
/// conversation until it exits; the next request starts a new one.
final class AgentBridge {
    /// Creates a bridge that runs `executable` with `environment`.
    ///
    /// - Parameter quota: Receives the Quota windows each time `claude` reports them.
    /// - Parameter search: Answers the `cerca` tool: the text to look for, and the Progetto's folder to search in, if any.
    init(executable: URL, arguments: [String] = [], environment: [String: String], trustGate: TrustGate = TrustGate(),
         quota: @escaping (Quota) -> Void = { _ in },
         search: @escaping (_ query: String, _ project: String?) async -> String) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.trustGate = trustGate
        self.quota = quota
        self.search = search
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let trustGate: TrustGate
    private let quota: (Quota) -> Void
    private let search: (String, String?) async -> String
    private var process: SpawnedProcess?
    private var answers: [String: AsyncThrowingStream<String, any Error>.Continuation] = [:]
    private var isClosing = false

    /// Asks `claude` to answer `prompt` in `directory`, streaming the answer as it arrives.
    ///
    /// `claude` loads the settings of `directory` only if it is trusted (`TrustGate`), never by the SDK's default;
    /// in a worktree it reads them from the main checkout.
    ///
    /// Cancelling the iteration interrupts the conversation.
    ///
    /// - Parameter model: A `claude` model alias, such as `sonnet`; `nil` for the user's own choice.
    func ask(_ prompt: String, in directory: URL, model: String? = nil) -> AsyncThrowingStream<String, any Error> {
        let id = UUID().uuidString
        let (answer, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor in self?.cancel(id) }
        }
        do {
            let process = try runningProcess()
            answers[id] = continuation
            // Trust and settings both come from the main checkout when `directory` is a worktree.
            let command = BridgeCommand.ask(id: id, prompt: prompt, directory: directory,
                                            settingSources: trustGate.settingSources(for: directory),
                                            projectConfigRoot: TrustGate.mainCheckout(ofWorktree: directory)
                                                .map { URL(filePath: $0, directoryHint: .isDirectory) },
                                            model: model)
            try process.input.write(contentsOf: command.line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            answers[id] = nil
            continuation.finish(throwing: error)
        }
        return answer
    }

    /// Asks for the Quota without a Domanda; it reaches `quota` only if `claude` can tell it.
    func readQuota() throws {
        try runningProcess().input.write(contentsOf: BridgeCommand.readQuota.line())
    }

    /// Closes the bridge once the conversations in progress end; it serves no new ones.
    func closeWhenIdle() {
        isClosing = true
        closeIfIdle()
    }

    private func closeIfIdle() {
        guard isClosing, answers.isEmpty else { return }
        // Closing the input ends the bridge, and its `claude` with it.
        try? process?.input.close()
    }

    private func cancel(_ id: String) {
        guard answers.removeValue(forKey: id) != nil, let process else { return }
        try? process.input.write(contentsOf: BridgeCommand.cancel(id: id).line())
        closeIfIdle()
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
        case let .limit(id, limit):
            answers.removeValue(forKey: id)?.finish(throwing: AgentBridgeError.limitReached(limit))
        case let .signInRequired(id):
            answers.removeValue(forKey: id)?.finish(throwing: AgentBridgeError.signInRequired)
        case let .search(id, query, project):
            Task {
                let text = await search(query, project)
                try? process?.input.write(contentsOf: BridgeCommand.found(id: id, text: text).line())
            }
        case let .quota(reported):
            quota(reported)
        case let .unsupportedVersion(version):
            finishAll(throwing: .unsupportedVersion(version))
        }
        closeIfIdle()
    }

    private func finishAll(throwing error: AgentBridgeError) {
        let pending = answers
        answers = [:]
        pending.values.forEach { $0.finish(throwing: error) }
    }
}
