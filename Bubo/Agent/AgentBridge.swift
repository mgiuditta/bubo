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
    /// `claude` reported this failure of a turn, with the SDK's reasons.
    case turnFailed(TurnFailure)
    /// The bridge speaks another protocol version.
    case unsupportedVersion(Int)
    /// `claude` stopped at a subscription limit.
    case limitReached(Quota.Limit)
    /// The login of `claude` is no longer valid.
    case signInRequired
    /// The turn stopped at the cap of its Budget, or was never sent because a Budget it counts in is spent (spec 18).
    case budgetExhausted
    /// The Sandbox could not start, for this reason as `claude` wrote it: nothing ran.
    case sandboxUnavailable(reason: String)
    /// `claude` is too old: nothing ran. `version` is `nil` when `claude` did not say it.
    case claudeOutdated(version: String?)
}

/// What a conversation asks of the user while it waits.
enum PermissionEvent: Equatable {
    /// A Richiesta di permesso to answer.
    case asked(PermissionRequest)
    /// Questions of the agent to answer.
    case question(AgentQuestion)
    /// `claude` no longer waits for the Richiesta, or the questions, with this id.
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
    /// - Parameter remember: Answers the `ricorda` tool: what it answers the model, and the write when there was one.
    /// - Parameter basics: The Profilo and the Regole of the Secondo cervello for the system prompt of each turn; `nil`
    ///   for none.
    /// - Parameter catalog: Receives the Claude models the account offers, read with the Quota.
    init(executable: URL, arguments: [String] = [], environment: [String: String], trustGate: TrustGate = TrustGate(),
         quota: @escaping (Quota) -> Void = { _ in }, catalog: @escaping (ModelCatalog) -> Void = { _ in },
         remember: @escaping (NoteRequest) async -> (reply: String, change: BrainChange?) = { _ in
             ("Non posso salvare note.", nil)
         },
         basics: @escaping () -> String? = { nil },
         search: @escaping (_ query: String, _ project: String?, _ source: SearchSource?) async -> String) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.trustGate = trustGate
        self.quota = quota
        self.catalog = catalog
        self.remember = remember
        self.basics = basics
        self.search = search
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let trustGate: TrustGate
    /// The accepted Risorse di squadra, read again at each turn.
    private let ledger = TrustLedger.standard
    private let quota: (Quota) -> Void
    private let catalog: (ModelCatalog) -> Void
    private let search: (String, String?, SearchSource?) async -> String
    private let remember: (NoteRequest) async -> (reply: String, change: BrainChange?)
    private let basics: () -> String?
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
    /// What receives the tokens of each answer in `answers` at each answer, before its figure.
    private var estimateHandlers: [String: (TurnUsage) -> Void] = [:]
    /// What learns which model answered each answer in `answers`, and with which effort.
    private var answeringHandlers: [String: (AnsweringModel) -> Void] = [:]
    /// What does the Anteprima's actions of each answer in `answers`; without one, they fail.
    private var previewHandlers: [String: (PreviewAction) async -> PreviewReply] = [:]
    /// The requests waiting for their one event: configurations, Cronologia CLI, transcripts.
    private var requests: [String: CheckedContinuation<BridgeEvent, any Error>] = [:]
    private var isClosing = false
    /// The `claude` of the latest conversation, from its `init`: it changes when `claude` updates with Bubo open.
    private(set) var claude: (version: String, capabilities: Set<ClaudeCapability>)?
    /// The bridge's process identifier while it runs: each `claude` in progress is one of its children.
    var pid: pid_t? { process?.pid }
    /// Whether `claude` answers with the API key, paid per use and counted in the Budgets (ADR 0003).
    var usesAPIKey: Bool { environment["ANTHROPIC_API_KEY"] != nil }

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
    ///   - effort: The effort to ask for; `nil` for the model's default.
    ///   - environment: Variables added to the environment of `claude`, such as a Sessione's ports.
    ///   - conversation: The id of a conversation to continue as a fork, leaving it untouched: from the Cronologia CLI,
    ///     or the previous turn of a Sessione.
    ///   - message: The message of `conversation` the fork stops at, included: Continua da qui. `nil` for all of it.
    ///   - kept: The id, a UUID, to give the agent's conversation so that Bubo keeps a copy of it (ADR 0006);
    ///     `nil` writes nothing of it.
    ///   - isSandboxed: Whether the commands of `claude` run in the Sandbox; if it cannot start, neither does the
    ///     conversation, with `AgentBridgeError.sandboxUnavailable`.
    ///   - sandboxAllowances: The hosts and folders the Sandbox also reaches, beyond the preset.
    ///   - id: The answer's id, to offer it the Anteprima later with ``offerPreview(_:to:)``.
    ///   - offersPreview: Whether the conversation starts with the Anteprima's tools: the Sessione has a server.
    ///   - remembers: Whether `claude` can write in the Secondo cervello with `ricorda`; each write reaches `progress`
    ///     as a line Salvato.
    ///   - permissionMode: How `claude` approves the calls; `nil` lets `claude` pick.
    ///   - rosa: The Varianti the agent may give the Orb while it works, with the tag `⟦orb:nome⟧`.
    ///   - unattended: Makes the turn one with nobody in front of it, an Esecuzione's: `claude` never asks, and a
    ///     Richiesta that arrives anyway is refused at once. Its denials and mode reach `progress`.
    ///   - maxBudget: What the tightest Budget has left, in US dollars: `claude` stops past it with
    ///     `AgentBridgeError.budgetExhausted`, at most one answer over. `nil` for no cap.
    ///   - readOnly: Makes the turn one that reads files and never changes them, a Domanda's; `nil` for the tools of
    ///     `claude`.
    ///   - progress: Receives what the conversation is doing and its summary, until the answer ends.
    ///   - permissions: Receives the Richieste di permesso, answered with `answerPermission(_:allows:isLasting:)`,
    ///     and the agent's questions, answered with `answerQuestion(_:with:)`; `nil` refuses them all.
    ///   - usage: Receives the tokens and the figure of the turn so far, each time `claude` reports them; the
    ///     latest replaces the ones before.
    ///   - estimate: Receives the tokens of the turn so far at each answer of `claude`, until `usage` gives its
    ///     figure: only tokens, never recorded as the turn's figure.
    ///   - preview: Does what the agent asks of the Anteprima; `nil` fails every call.
    ///   - answeredBy: Learns the model that answered and its effective effort, once, just before the answer ends.
    ///   - isDangerous: Tells the bridge's gate whether a call is level 4 or 5, so that it asks even when the
    ///     Sandbox or the Modalità autonoma would let it run; `nil` counts every call as dangerous.
    func ask(_ prompt: String, in directory: URL, model: String? = nil, effort: Effort? = nil, environment: [String: String] = [:],
             forkingFrom conversation: String? = nil, upTo message: String? = nil, keeping kept: String? = nil,
             isSandboxed: Bool = false,
             sandboxAllowances: SandboxAllowances = SandboxAllowances(), permissionMode: PermissionMode? = nil,
             id: String = UUID().uuidString, offersPreview: Bool = false, remembers: Bool = false,
             rosa: [Variante] = Catalogo.bundled?.rosa() ?? [], unattended: UnattendedTurn? = nil,
             readableDirectories: [URL] = [], maxBudget: Decimal? = nil, readOnly: ReadOnlyTurn? = nil,
             progress: @escaping (AgentProgress) -> Void = { _ in },
             permissions: ((PermissionEvent) -> Void)? = nil,
             usage: @escaping (TurnUsage) -> Void = { _ in },
             estimate: @escaping (TurnUsage) -> Void = { _ in },
             preview: ((PreviewAction) async -> PreviewReply)? = nil,
             answeredBy: @escaping (AnsweringModel) -> Void = { _ in },
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
            // Nobody answers in an Esecuzione: without a handler, a Richiesta is refused as it arrives.
            permissionHandlers[id] = unattended == nil ? permissions : nil
            usageHandlers[id] = usage
            estimateHandlers[id] = estimate
            answeringHandlers[id] = answeredBy
            previewHandlers[id] = preview
            riskHandlers[id] = isDangerous
            // Trust and settings both come from the main checkout when `directory` is a worktree.
            let command = BridgeCommand.ask(id: id, prompt: prompt, directory: directory,
                                            settingSources: trustGate.settingSources(for: directory),
                                            projectConfigRoot: TrustGate.mainCheckout(ofWorktree: directory)
                                                .map { URL(filePath: $0, directoryHint: .isDirectory) },
                                            model: model, environment: environment, resuming: conversation,
                                            resumingAt: message, keeping: kept,
                                            sandbox: isSandboxed ? sandbox(for: environment, allowances: sandboxAllowances) : nil,
                                            offersPreview: offersPreview,
                                            teamRules: TeamResourceReader.sessionRules(for: directory, ledger: ledger),
                                            remembers: remembers, permissionMode: permissionMode, effort: effort,
                                            rosa: rosa.map(\.nome), unattended: unattended,
                                            readableDirectories: readableDirectories, maxBudget: maxBudget,
                                            secondBrain: basics(), readOnly: readOnly)
            try process.input.write(contentsOf: command.line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            removeAnswer(id)
            continuation.finish(throwing: error)
        }
        return answer
    }

    /// Asks the user's `copilot` to answer `prompt` in `directory`, streaming the answer as it arrives (ADR 0012).
    ///
    /// `copilot` runs with the user's own login: the bridge removes the tokens that would override it. Cancelling the
    /// iteration is Ferma: the bridge aborts the turn, and closes `copilot` if it does not stop in time. Without the
    /// user's consent for Copilot nothing is sent, and the answer fails with `CopilotFailure.consentMissing`.
    ///
    /// - Parameters:
    ///   - copilot: The user's `copilot`.
    ///   - consents: The clouds the user allowed, from ``EndpointSettings/consents``.
    ///   - model: A Copilot model id; `nil` for the user's own choice.
    ///   - effort: The reasoning effort; `nil` for the model's default.
    ///   - conversation: The conversation Bubo keeps a copy of (ADR 0006), also the id of the session of `copilot`;
    ///     `nil` for none.
    ///   - resuming: Whether `copilot` resumes `conversation` with what was said in it, instead of starting it.
    ///   - progress: Receives the state of the conversation, until the answer ends.
    ///   - permissions: Receives the Richieste di permesso, answered with `answerPermission(_:allows:isLasting:)`;
    ///     `nil` refuses them all.
    ///   - usage: Receives the tokens of the turn, with no figure, when it ends: Bubo prices them (#542).
    func askCopilot(_ prompt: String, in directory: URL, copilot: URL, consents: Set<String>, model: String? = nil,
                    effort: Effort? = nil, keeping conversation: String? = nil, resuming: Bool = false,
                    id: String = UUID().uuidString,
                    progress: @escaping (AgentProgress) -> Void = { _ in },
                    permissions: ((PermissionEvent) -> Void)? = nil,
                    usage: @escaping (TurnUsage) -> Void = { _ in }) -> AsyncThrowingStream<String, any Error> {
        let (answer, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor in self?.cancel(id) }
        }
        guard consents.contains(EndpointSettings.copilotConsentID) else {
            continuation.finish(throwing: CopilotFailure.consentMissing)
            return answer
        }
        do {
            let process = try runningProcess()
            answers[id] = continuation
            progressHandlers[id] = progress
            permissionHandlers[id] = permissions
            usageHandlers[id] = usage
            let command = BridgeCommand.askCopilot(id: id, prompt: prompt, directory: directory, copilot: copilot,
                                                   model: model, effort: effort, keeping: conversation,
                                                   resumes: resuming)
            try process.input.write(contentsOf: command.line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            removeAnswer(id)
            continuation.finish(throwing: error)
        }
        return answer
    }

    /// Asks `model` to answer `prompt` in one turn with no tools, no settings and no copy of the conversation, in an
    /// empty folder of Bubo: the Riassunto di Sessione. The answer streams as the one of `ask` does.
    ///
    /// - Parameter usage: Receives the tokens and the figure of the turn, each time `claude` reports them.
    func summarize(_ prompt: String, model: String?,
                   usage: @escaping (TurnUsage) -> Void = { _ in }) -> AsyncThrowingStream<String, any Error> {
        let id = UUID().uuidString
        let (answer, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor in self?.cancel(id) }
        }
        do {
            let directory = URL.temporaryDirectory.appending(path: "bubo-riassunto", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let process = try runningProcess()
            answers[id] = continuation
            usageHandlers[id] = usage
            try process.input.write(contentsOf: BridgeCommand.summarize(id: id, prompt: prompt, directory: directory,
                                                                        model: model).line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            removeAnswer(id)
            continuation.finish(throwing: error)
        }
        return answer
    }

    /// Asks the user's `copilot` to answer the Domanda `prompt`, streaming the answer as it arrives (ADR 0011).
    ///
    /// The session has no tools, and runs in an empty folder of Bubo: no Progetto's instructions reach it. `copilot`
    /// answers with the user's own login: the bridge removes the tokens that would override it. Cancelling the
    /// iteration stops the answer. Without the user's consent for Copilot nothing is sent, and the answer fails with
    /// `CopilotFailure.consentMissing`.
    ///
    /// - Parameters:
    ///   - copilot: The user's `copilot`.
    ///   - consents: The clouds the user allowed, from ``EndpointSettings/consents``.
    ///   - model: A Copilot model id, from ``copilotModels(of:)``; `nil` for the user's own choice in `copilot`.
    ///   - effort: The reasoning effort; `nil` for the model's default.
    ///   - usage: Receives the tokens of the answer, once, before it ends; without a figure (Spesa, #542).
    ///   - answeredBy: Learns the model that answered and its effort, once, just before the answer ends.
    func askCopilotQuestion(_ prompt: String, copilot: URL, consents: Set<String>, model: String? = nil,
                            effort: Effort? = nil,
                            usage: @escaping (TurnUsage) -> Void = { _ in },
                            answeredBy: @escaping (AnsweringModel) -> Void = { _ in }) -> AsyncThrowingStream<String, any Error> {
        let id = UUID().uuidString
        let (answer, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor in self?.cancel(id) }
        }
        guard consents.contains(EndpointSettings.copilotConsentID) else {
            continuation.finish(throwing: CopilotFailure.consentMissing)
            return answer
        }
        do {
            let directory = URL.temporaryDirectory.appending(path: "bubo-domanda-copilot", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let process = try runningProcess()
            answers[id] = continuation
            usageHandlers[id] = usage
            answeringHandlers[id] = answeredBy
            let command = BridgeCommand.askCopilotQuestion(id: id, prompt: prompt, directory: directory, copilot: copilot,
                                                           model: model, effort: effort)
            try process.input.write(contentsOf: command.line())
        } catch let ProcessSpawnerError.failed(code) {
            continuation.finish(throwing: AgentBridgeError.spawnFailed(errno: code))
        } catch {
            removeAnswer(id)
            continuation.finish(throwing: error)
        }
        return answer
    }

    /// The models the Copilot plan of the user's `copilot` offers, as `listModels()` lists them: no turn of the model.
    func copilotModels(of copilot: URL) async throws -> [CopilotModel] {
        let id = UUID().uuidString
        guard case let .copilotModels(_, models) = try await request(.readCopilotModels(id: id, copilot: copilot), id: id)
        else {
            throw AgentBridgeError.failed(message: "unexpected event")
        }
        return models
    }

    /// The Sandbox of a `claude` that gets the bridge's environment and `environment`, reaching also `allowances`.
    private func sandbox(for environment: [String: String], allowances: SandboxAllowances) -> SandboxPolicy {
        SandboxPolicy(environment: self.environment.merging(environment) { $1 }, allowances: allowances)
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

    /// Has the turns in progress connect again to the MCP server `name`, after a login; with no bridge running, there is
    /// none, and the next turn connects by itself.
    func reconnectMCPServer(named name: String) throws {
        try process?.input.write(contentsOf: BridgeCommand.reconnectMCPServer(name: name).line())
    }

    /// Reloads the plugins of the answer `id` in progress: Ricarica plugin, which `claude` holds when it would lose the
    /// prompt cache, or Ricarica comunque when `isForced`.
    ///
    /// - Throws: `AgentBridgeError.failed` when the answer has ended, or `claude` could not reload.
    func reloadPlugins(ofAnswer id: String, isForced: Bool) async throws -> PluginReload {
        let request = UUID().uuidString
        let command = BridgeCommand.reloadPlugins(id: request, turn: id, isForced: isForced)
        guard case let .pluginsReloaded(_, reload) = try await self.request(command, id: request) else {
            throw AgentBridgeError.failed(message: "unexpected event")
        }
        return reload
    }

    /// Where `claude` reads the Progetto's settings for `directory`: the main checkout when it is a worktree.
    private static func projectConfigRoot(of directory: URL) -> URL? {
        TrustGate.mainCheckout(ofWorktree: directory).map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// The Regole di permesso of `claude` in `directory` that widen the Sandbox, with the same settings as a Sessione
    /// there. `claude` answers on its control channel, so no turn of the model and no Quota spent.
    func sandboxRules(in directory: URL) async throws -> [SandboxWideningRule] {
        let id = UUID().uuidString
        let command = BridgeCommand.readSandboxRules(id: id, directory: directory,
                                                     settingSources: trustGate.settingSources(for: directory),
                                                     projectConfigRoot: TrustGate.mainCheckout(ofWorktree: directory)
                                                         .map { URL(filePath: $0, directoryHint: .isDirectory) })
        guard case let .sandboxRules(_, rules) = try await request(command, id: id) else {
            throw AgentBridgeError.failed(message: "unexpected event")
        }
        return rules
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

    /// The text of the latest messages of `conversation`, or of all of them when `isComplete`, oldest first.
    ///
    /// The bridge reads them with the SDK, from `~/.claude` or from Bubo's copy, never from the JSONL.
    func transcript(of conversation: String, isComplete: Bool = false) async throws -> [CLIConversation.Message] {
        let id = UUID().uuidString
        let command = BridgeCommand.readTranscript(id: id, conversation: conversation, isComplete: isComplete)
        guard case let .transcript(_, messages) = try await request(command, id: id)
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

    /// Answers the Richiesta di permesso `request`; `isLasting` when the user allowed it for the rest of the Sessione.
    /// If the bridge is gone, so is the call waiting for it: nothing runs.
    func answerPermission(_ request: PermissionRequest.ID, allows: Bool, isLasting: Bool = false) {
        do {
            try process?.input.write(contentsOf: BridgeCommand.answerPermission(request: request, allows: allows,
                                                                                isLasting: isLasting).line())
        } catch {
            Logger.agent.error("Permission answer not sent: \(error)")
        }
    }

    /// Answers the agent's questions `question` with `replies`, one per question in order; `nil` when the user does not
    /// answer. If the bridge is gone, so is the agent waiting for them.
    func answerQuestion(_ question: AgentQuestion.ID, with replies: [AgentQuestion.Reply]?) {
        do {
            try process?.input.write(contentsOf: BridgeCommand.answerQuestion(request: question, replies: replies).line())
        } catch {
            Logger.agent.error("Question answer not sent: \(error)")
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

    /// Asks for the Quota and the catalog of models without a Domanda; each reaches `quota` and `catalog` only if
    /// `claude` can tell it.
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
        case let .turnFailed(id, failure):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.turnFailed(failure))
        case let .error(nil, message):
            finishAll(throwing: .failed(message: message))
        case let .limit(id, limit):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.limitReached(limit))
        case let .signInRequired(id):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.signInRequired)
        case let .budgetExhausted(id):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.budgetExhausted)
        case let .sandboxUnavailable(id, reason):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.sandboxUnavailable(reason: reason))
        case let .claude(_, version, capabilities):
            claude = (version, capabilities)
        case let .outdated(id, version):
            removeAnswer(id)?.finish(throwing: AgentBridgeError.claudeOutdated(version: version))
        case let .search(id, query, project, source, conversation):
            Task {
                let text = await search(query, project, source)
                try? process?.input.write(contentsOf: BridgeCommand.found(id: id, text: text).line())
                if let conversation { progressHandlers[conversation]?(.memory(.searched(query: query, result: text))) }
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
        case let .remember(id, request, conversation):
            Task {
                let outcome = await remember(request)
                try? process?.input.write(contentsOf: BridgeCommand.found(id: id, text: outcome.reply).line())
                if let change = outcome.change, let conversation { progressHandlers[conversation]?(.memory(.saved(change))) }
            }
        case let .permission(id, request):
            if let handler = permissionHandlers[id] {
                handler(.asked(request))
            } else {
                answerPermission(request.id, allows: false)
            }
        case let .question(id, question):
            if let handler = permissionHandlers[id] {
                handler(.question(question))
            } else {
                answerQuestion(question.id, with: nil)
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
        case let .estimate(id, usage):
            estimateHandlers[id]?(usage)
        case let .answeredBy(id, model):
            answeringHandlers[id]?(model)
        case let .quota(reported):
            quota(reported)
        case let .models(models):
            catalog(models)
        case let .configuration(id, _), let .history(id, _), let .transcript(id, _), let .kept(id, _), let .forgot(id),
             let .sandboxRules(id, _), let .pluginsReloaded(id, _), let .copilotModels(id, _):
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
        estimateHandlers[id] = nil
        answeringHandlers[id] = nil
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
        estimateHandlers = [:]
        answeringHandlers = [:]
        previewHandlers = [:]
        riskHandlers = [:]
        pending.values.forEach { $0.finish(throwing: error) }
        let waiting = requests
        requests = [:]
        waiting.values.forEach { $0.resume(throwing: error) }
    }
}
