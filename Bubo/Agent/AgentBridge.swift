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
    /// The Sandbox could not start, for this reason as `claude` wrote it: nothing ran.
    case sandboxUnavailable(reason: String)
}

/// What a conversation asks of the user while it waits.
enum PermissionEvent: Equatable {
    /// A Richiesta di permesso to answer.
    case asked(PermissionRequest)
    /// `claude` no longer waits for the Richiesta with this id.
    case withdrawn(PermissionRequest.ID)
}

/// Talks to the agent bridge, a child process that drives `claude` through the Agent SDK.
///
/// The bridge starts on the first request, disclaimed (ADR 0005), and serves every
/// conversation until it exits; the next request starts a new one.
final class AgentBridge {
    /// Creates a bridge that runs `executable` with `environment`.
    ///
    /// - Parameter quota: Receives the Quota windows each time `claude` reports them.
    /// - Parameter search: Answers the `cerca` tool: the text to look for, and the Progetto's folder and the source to
    ///   search in, if any.
    /// - Parameter remember: Answers the `ricorda` tool of a Domanda: the text to save and its title.
    init(executable: URL, arguments: [String] = [], environment: [String: String], trustGate: TrustGate = TrustGate(),
         quota: @escaping (Quota) -> Void = { _ in },
         remember: @escaping (_ text: String, _ title: String) async -> String = { _, _ in "Non posso salvare note." },
         search: @escaping (_ query: String, _ project: String?, _ source: SearchSource?) async -> String) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.trustGate = trustGate
        self.quota = quota
        self.remember = remember
        self.search = search
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let trustGate: TrustGate
    /// The accepted Risorse di squadra, read again at each turn.
    private let ledger = TrustLedger.standard
    private let quota: (Quota) -> Void
    private let search: (String, String?, SearchSource?) async -> String
    private let remember: (String, String) async -> String
    private var process: SpawnedProcess?
    private var answers: [String: AsyncThrowingStream<String, any Error>.Continuation] = [:]
    /// What receives the progress of each answer in `answers`.
    private var progressHandlers: [String: (AgentProgress) -> Void] = [:]
    /// What receives the Richieste di permesso of each answer in `answers`; without one, they are refused.
    private var permissionHandlers: [String: (PermissionEvent) -> Void] = [:]
    /// What tells the gate of each answer in `answers` whether a call is level 4 or 5; without one, every call is.
    private var riskHandlers: [String: (PermissionRequest) -> Bool] = [:]
    /// What receives the tokens and the figure of each answer in `answers`.
    private var usageHandlers: [String: (TurnUsage) -> Void] = [:]
    /// What does the Anteprima's actions of each answer in `answers`; without one, they fail.
    private var previewHandlers: [String: (PreviewAction) async -> PreviewReply] = [:]
    /// The requests waiting for their one event: configurations, Cronologia CLI, transcripts.
    private var requests: [String: CheckedContinuation<BridgeEvent, any Error>] = [:]
    private var isClosing = false

    /// Asks `claude` to answer `prompt` in `directory`, streaming the answer as it arrives.
    ///
    /// `claude` loads the settings of `directory` only if it is trusted (`TrustGate`), never by the SDK's default;
    /// in a worktree it reads them from the main checkout. The Progetto's Risorse di squadra in force go with it as
    /// session rules, read again at each call.
    ///
    /// Cancelling the iteration interrupts the conversation.
    ///
    /// - Parameters:
    ///   - model: A `claude` model alias, such as `sonnet`; `nil` for the user's own choice.
    ///   - environment: Variables added to the environment of `claude`, such as a Sessione's ports.
    ///   - conversation: The id of a Cronologia CLI conversation to continue as a fork, leaving it untouched.
    ///   - kept: The id, a UUID, to give the agent's conversation so that Bubo keeps a copy of it (ADR 0006);
    ///     `nil` writes nothing of it.
    ///   - isSandboxed: Whether the commands of `claude` run in the Sandbox; if it cannot start, neither does the
    ///     conversation, with `AgentBridgeError.sandboxUnavailable`.
    ///   - id: The answer's id, to offer it the Anteprima later with ``offerPreview(_:to:)``.
    ///   - offersPreview: Whether the conversation starts with the Anteprima's tools: the Sessione has a server.
    ///   - remembers: Whether `claude` can save a note in the Secondo cervello with `ricorda`: only in a Domanda.
    ///   - permissionMode: How `claude` approves the calls; `nil` lets `claude` pick.
    ///   - progress: Receives what the conversation is doing and its summary, until the answer ends.
    ///   - permissions: Receives the Richieste di permesso, answered with `answerPermission(_:allows:)`;
    ///     `nil` refuses them all.
    ///   - usage: Receives the tokens and the figure of the turn so far, each time `claude` reports them; the
    ///     latest replaces the ones before.
    ///   - preview: Does what the agent asks of the Anteprima; `nil` fails every call.
    ///   - isDangerous: Tells the bridge's gate whether a call is level 4 or 5, so that it asks even when the
    ///     Sandbox or the Modalità autonoma would let it run; `nil` counts every call as dangerous.
    func ask(_ prompt: String, in directory: URL, model: String? = nil, environment: [String: String] = [:],
             forkingFrom conversation: String? = nil, keeping kept: String? = nil, isSandboxed: Bool = false,
             permissionMode: PermissionMode? = nil, id: String = UUID().uuidString, offersPreview: Bool = false,
             remembers: Bool = false,
             progress: @escaping (AgentProgress) -> Void = { _ in },
             permissions: ((PermissionEvent) -> Void)? = nil,
             usage: @escaping (TurnUsage) -> Void = { _ in },
             preview: ((PreviewAction) async -> PreviewReply)? = nil,
             isDangerous: ((PermissionRequest) -> Bool)? = nil) -> AsyncThrowingStream<String, any Error> {
        let (answer, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor in self?.cancel(id) }
        }
        do {
            let process = try runningProcess()
            answers[id] = continuation
            progressHandlers[id] = progress
            permissionHandlers[id] = permissions
            usageHandlers[id] = usage
            previewHandlers[id] = preview
            riskHandlers[id] = isDangerous
            // Trust and settings both come from the main checkout when `directory` is a worktree.
            let command = BridgeCommand.ask(id: id, prompt: prompt, directory: directory,
                                            settingSources: trustGate.settingSources(for: directory),
                                            projectConfigRoot: TrustGate.mainCheckout(ofWorktree: directory)
                                                .map { URL(filePath: $0, directoryHint: .isDirectory) },
                                            model: model, environment: environment, resuming: conversation,
                                            keeping: kept,
                                            sandbox: isSandboxed ? sandbox(for: environment) : nil,
                                            offersPreview: offersPreview,
                                            teamRules: TeamResourceReader.sessionRules(for: directory, ledger: ledger),
                                            remembers: remembers, permissionMode: permissionMode)
            try process.input.write(contentsOf: command.line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            removeAnswer(id)
            continuation.finish(throwing: error)
        }
        return answer
    }

    /// The Sandbox of a `claude` that gets the bridge's environment and `environment`.
    private func sandbox(for environment: [String: String]) -> SandboxPolicy {
        SandboxPolicy(environment: self.environment.merging(environment) { $1 })
    }

    /// The configuration `claude` loads in `directory`: CLAUDE.md, skills, plugins and MCP servers, as it reports them.
    ///
    /// Same settings as `ask(_:in:model:environment:forkingFrom:)`: the Progetto's own only if trusted, from the main checkout
    /// in a worktree. `claude` runs a local command, so no turn of the model and no Quota spent.
    /// A `claude` kept ready by ``warmConfiguration(for:)`` for the same settings answers in place of a new one.
    func configuration(of directory: URL) async throws -> ClaudeConfiguration {
        let id = UUID().uuidString
        let settingSources = trustGate.settingSources(for: directory)
        let command = BridgeCommand.inspect(id: id, directory: directory, settingSources: settingSources,
                                            projectConfigRoot: Self.projectConfigRoot(of: directory))
        guard case var .configuration(_, configuration) = try await request(command, id: id) else {
            throw AgentBridgeError.failed(message: "unexpected event")
        }
        configuration.loadsProject = settingSources.contains("project")
        return configuration
    }

    /// Has the bridge keep one `claude` ready with the settings of `directory`, so that the next
    /// ``configuration(of:)`` with the same settings skips the start of the CLI (#311).
    ///
    /// `claude` only starts, with no turn of the model; it serves one ``configuration(of:)`` and then is gone.
    func warmConfiguration(for directory: URL) throws {
        let command = BridgeCommand.warmConfiguration(settingSources: trustGate.settingSources(for: directory),
                                                      projectConfigRoot: Self.projectConfigRoot(of: directory))
        try runningProcess().input.write(contentsOf: command.line())
    }

    /// Closes the `claude` kept ready by ``warmConfiguration(for:)``; with no bridge running, there is none.
    func coolConfiguration() throws {
        try process?.input.write(contentsOf: BridgeCommand.coolConfiguration.line())
    }

    /// Where `claude` reads the Progetto's settings for `directory`: the main checkout when it is a worktree.
    private static func projectConfigRoot(of directory: URL) -> URL? {
        TrustGate.mainCheckout(ofWorktree: directory).map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// The Cronologia CLI, most recent first, as the SDK lists it: only what the user ran in a terminal.
    ///
    /// - Parameter isComplete: Whether to list it all, for a search; otherwise the 50 most recent.
    func history(isComplete: Bool = false) async throws -> [CLIConversation] {
        let id = UUID().uuidString
        guard case let .history(_, conversations) = try await request(.readHistory(id: id, isComplete: isComplete),
                                                                      id: id)
        else { throw AgentBridgeError.failed(message: "unexpected event") }
        return conversations
    }

    /// The text of the latest messages of `conversation` in the Cronologia CLI, oldest first.
    func transcript(of conversation: String) async throws -> [CLIConversation.Message] {
        let id = UUID().uuidString
        guard case let .transcript(_, messages) = try await request(.readTranscript(id: id, conversation: conversation),
                                                                    id: id)
        else { throw AgentBridgeError.failed(message: "unexpected event") }
        return messages
    }

    /// Copies in Bubo's database the Cronologia CLI not copied yet, or changed since, and returns how many conversations.
    func keepHistory() async throws -> Int {
        let id = UUID().uuidString
        guard case let .kept(_, count) = try await request(.keepHistory(id: id), id: id) else {
            throw AgentBridgeError.failed(message: "unexpected event")
        }
        return count
    }

    /// Deletes the copies of the Cronologia CLI from Bubo's database, and returns once they are gone.
    func forgetHistory() async throws {
        let id = UUID().uuidString
        guard case .forgot = try await request(.forgetHistory(id: id), id: id) else {
            throw AgentBridgeError.failed(message: "unexpected event")
        }
    }

    /// Deletes the copies of `conversations` from Bubo's database.
    func forget(_ conversations: [String]) throws {
        try runningProcess().input.write(contentsOf: BridgeCommand.forget(conversations: conversations).line())
    }

    /// Sends `command` and waits for the one event that answers it.
    private func request(_ command: BridgeCommand, id: String) async throws -> BridgeEvent {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let process = try runningProcess()
                requests[id] = continuation
                try process.input.write(contentsOf: command.line())
            } catch let ProcessSpawnerError.failed(code) {
                continuation.resume(throwing: AgentBridgeError.spawnFailed(errno: code))
            } catch {
                requests[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Answers the Richiesta di permesso `request`. If the bridge is gone, so is the call waiting for it: nothing runs.
    func answerPermission(_ request: PermissionRequest.ID, allows: Bool) {
        do {
            try process?.input.write(contentsOf: BridgeCommand.answerPermission(request: request, allows: allows).line())
        } catch {
            Logger.agent.error("Permission answer not sent: \(error)")
        }
    }

    /// Adds the Anteprima's tools to the answer `id` in progress, or removes them; nothing once it has ended.
    func offerPreview(_ isOffered: Bool, to id: String) {
        guard answers[id] != nil, let process else { return }
        do {
            try process.input.write(contentsOf: BridgeCommand.offerPreview(id: id, isOffered: isOffered).line())
        } catch {
            Logger.agent.error("Anteprima tools not updated: \(error)")
        }
    }

    /// Starts the bridge without asking it anything, so the first request finds it ready; `claude` does not start.
    func start() throws {
        _ = try runningProcess()
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
        guard isClosing, answers.isEmpty, requests.isEmpty else { return }
        // Closing the input ends the bridge, and its `claude` with it.
        try? process?.input.close()
    }

    private func cancel(_ id: String) {
        guard removeAnswer(id) != nil, let process else { return }
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
            removeAnswer(id)?.finish()
        case let .progress(id, progress):
            progressHandlers[id]?(progress)
        case let .error(id?, message):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.failed(message: message))
            requests.removeValue(forKey: id)?.resume(throwing: AgentBridgeError.failed(message: message))
        case let .error(nil, message):
            finishAll(throwing: .failed(message: message))
        case let .limit(id, limit):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.limitReached(limit))
        case let .signInRequired(id):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.signInRequired)
        case let .sandboxUnavailable(id, reason):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.sandboxUnavailable(reason: reason))
        case let .search(id, query, project, source):
            Task {
                let text = await search(query, project, source)
                try? process?.input.write(contentsOf: BridgeCommand.found(id: id, text: text).line())
            }
        case let .previewCall(id, call, action):
            let handler = previewHandlers[id]
            Task {
                let reply: PreviewReply = if let action, let handler {
                    await handler(action)
                } else {
                    .failure("Strumento dell'Anteprima non disponibile.")
                }
                do {
                    try process?.input.write(contentsOf: BridgeCommand.answerPreview(call: call, reply).line())
                } catch {
                    Logger.agent.error("Anteprima answer not sent: \(error)")
                }
            }
        case let .remember(id, title, text):
            Task {
                let result = await remember(text, title)
                try? process?.input.write(contentsOf: BridgeCommand.found(id: id, text: result).line())
            }
        case let .permission(id, request):
            if let handler = permissionHandlers[id] {
                handler(.asked(request))
            } else {
                answerPermission(request.id, allows: false)
            }
        case let .permissionWithdrawn(id, request):
            permissionHandlers[id]?(.withdrawn(request))
        case let .risk(id, request):
            let isDangerous = riskHandlers[id]?(request) ?? true
            do {
                try process?.input.write(contentsOf: BridgeCommand.answerRisk(request: request.id, isDangerous: isDangerous)
                    .line())
            } catch {
                Logger.agent.error("Risk answer not sent: \(error)")
            }
        case let .usage(id, usage):
            usageHandlers[id]?(usage)
        case let .quota(reported):
            quota(reported)
        case let .configuration(id, _), let .history(id, _), let .transcript(id, _), let .kept(id, _), let .forgot(id):
            requests.removeValue(forKey: id)?.resume(returning: event)
        case let .unsupportedVersion(version):
            finishAll(throwing: .unsupportedVersion(version))
        }
        closeIfIdle()
    }

    /// Stops following the answer `id`, returning its continuation if it was still open.
    @discardableResult
    private func removeAnswer(_ id: String) -> AsyncThrowingStream<String, any Error>.Continuation? {
        progressHandlers[id] = nil
        permissionHandlers[id] = nil
        usageHandlers[id] = nil
        previewHandlers[id] = nil
        riskHandlers[id] = nil
        return answers.removeValue(forKey: id)
    }

    private func finishAll(throwing error: AgentBridgeError) {
        let pending = answers
        answers = [:]
        progressHandlers = [:]
        permissionHandlers = [:]
        usageHandlers = [:]
        previewHandlers = [:]
        riskHandlers = [:]
        pending.values.forEach { $0.finish(throwing: error) }
        let waiting = requests
        requests = [:]
        waiting.values.forEach { $0.resume(throwing: error) }
    }
}
