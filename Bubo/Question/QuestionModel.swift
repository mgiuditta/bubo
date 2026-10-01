import Foundation
import os

/// A Domanda typed in the HUD, answered by `claude` through the agent bridge.
@Observable
final class QuestionModel {
    /// What the user is typing.
    var prompt = ""
    /// The answer so far, growing as it streams.
    private(set) var answer = ""
    /// Whether an answer is on its way.
    private(set) var isAnswering = false
    /// Why the last Domanda got no answer, if it failed.
    private(set) var failure: QuestionFailure?
    /// The Quota last reported by `claude` through the bridge this model owns; empty until it reports one.
    private(set) var quota = Quota()
    /// When the last prompt will be asked again, while waiting for a limit's reset.
    private(set) var resumesAt: Date?
    /// Whether `claude` runs with the API key, paid per use; only after the user's consent (ADR 0003).
    private(set) var usesAPIKey = false
    /// The note the last Domanda saved in the Secondo cervello ("Ricordati questo"), if any.
    private(set) var savedNote: URL?

    /// Creates a model that finds `claude` with `cli`, answers its `cerca` tool with `index` and its `ricorda` tool
    /// with `secondBrain`.
    ///
    /// - Parameters:
    ///   - bridgeExecutable: The agent bridge; tests pass a stand-in.
    ///   - bridgeArguments: The arguments of `bridgeExecutable`.
    ///   - apiKey: Reads the saved API key, from `APIKeyStore` when `nil`; called only after the user chose it.
    init(cli: ClaudeCLI = ClaudeCLI(), index: SearchIndex? = nil, secondBrain: SecondBrain? = nil,
         bridgeExecutable: URL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/bubo-agent"),
         bridgeArguments: [String] = [],
         apiKey: (() async throws -> String?)? = nil) {
        self.cli = cli
        self.index = index
        self.secondBrain = secondBrain
        self.bridgeExecutable = bridgeExecutable
        self.bridgeArguments = bridgeArguments
        let store = APIKeyStore()
        self.apiKey = apiKey ?? { try await store.key() }
    }

    /// The task answering the last Domanda, or waiting to ask it again.
    @ObservationIgnored private(set) var answering: Task<Void, Never>?
    @ObservationIgnored private let cli: ClaudeCLI
    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let secondBrain: SecondBrain?
    @ObservationIgnored private let bridgeExecutable: URL
    @ObservationIgnored private let bridgeArguments: [String]
    @ObservationIgnored private let apiKey: () async throws -> String?
    @ObservationIgnored private var bridge: AgentBridge?
    @ObservationIgnored private var lastPrompt = ""
    @ObservationIgnored private var quotaReadAt: Date?

    /// Asks the typed prompt, replacing any answer in progress.
    func ask() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastPrompt = text
        prompt = ""
        start(text)
    }

    /// Asks the last prompt again.
    func retry() {
        start(lastPrompt)
    }

    /// Asks the last prompt again with `model`, a `claude` alias such as `sonnet`.
    func retry(model: String) {
        start(lastPrompt, model: model)
    }

    /// Stops the answer in progress, keeping what arrived, or stops waiting for a reset.
    func stop() {
        answering?.cancel()
        resumesAt = nil
    }

    /// Stops the Domanda and hands it to a new Sessione: what is typed, and the last prompt with what arrived of its
    /// answer; with no answer, what is typed or else the last prompt.
    func turnIntoSession() -> SessionDraft {
        stop()
        let typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return SessionDraft(prompt: typed.isEmpty ? lastPrompt : typed) }
        return SessionDraft(prompt: typed, question: lastPrompt, answer: answer)
    }

    /// Waits until the limit that stopped the last Domanda resets, then asks it again.
    func resumeAfterReset() {
        guard case let .bridge(.limitReached(limit)) = failure, let resetsAt = limit.resetsAt else { return }
        answering?.cancel()
        resumesAt = resetsAt
        answering = Task {
            // A few seconds past the reset, so the window has surely started again; the wait runs on through sleep.
            try? await Task.sleep(for: .seconds(max(0, resetsAt.timeIntervalSinceNow) + 5))
            guard !Task.isCancelled else { return }
            resumesAt = nil
            start(lastPrompt)
        }
    }

    /// Moves the Domande and the Sessioni to the API key until Bubo quits, then asks the last prompt again.
    ///
    /// Called only when the user confirms (ADR 0003): Bubo never moves to the API key on its own.
    func useAPIKey() async {
        do {
            guard try await apiKey() != nil else {
                failure = .apiKeyMissing
                return
            }
        } catch {
            Logger.agent.error("API key not read: \(String(describing: error), privacy: .public)")
            failure = .unexpected
            return
        }
        moveToAPIKey()
        start(lastPrompt)
    }

    /// Moves the Domande and the Sessioni to the saved API key until Bubo quits, asking nothing again.
    ///
    /// Called only when the user chooses it (ADR 0003).
    func moveToAPIKey() {
        usesAPIKey = true
        // Conversations in progress end on the old bridge; the next one starts with the key.
        bridge?.closeWhenIdle()
        bridge = nil
    }

    /// Reads the Quota without a Domanda, at most once a minute; with no answer it stays hidden.
    func refreshQuota() async {
        if let quotaReadAt, quotaReadAt.timeIntervalSinceNow > -60 { return }
        quotaReadAt = .now
        do {
            try await readyBridge().readQuota()
        } catch {
            Logger.agent.notice("Quota not read: \(String(describing: error), privacy: .public)")
        }
    }

    private func start(_ text: String, model: String? = nil) {
        answering?.cancel()
        answer = ""
        failure = nil
        resumesAt = nil
        savedNote = nil
        isAnswering = true
        answering = Task { await stream(text, model: model) }
    }

    private func stream(_ text: String, model: String?) async {
        defer { isAnswering = false }
        let signpostID = Signposts.signposter.makeSignpostID()
        var waitingForFirstToken: OSSignpostIntervalState? =
            Signposts.signposter.beginInterval("Domanda, primo token", id: signpostID)
        defer { waitingForFirstToken.map { Signposts.signposter.endInterval("Domanda, primo token", $0) } }
        do {
            let bridge = try await readyBridge()
            for try await chunk in bridge.ask(text, in: try Self.directory(), model: model, remembers: true) {
                if let state = waitingForFirstToken {
                    Signposts.signposter.endInterval("Domanda, primo token", state)
                    waitingForFirstToken = nil
                }
                answer += chunk
            }
        } catch is CancellationError {
        } catch let failure as QuestionFailure {
            self.failure = failure
        } catch let error as AgentBridgeError {
            Logger.agent.error("Domanda failed: \(String(describing: error), privacy: .public)")
            // With no network `claude` gives up with a generic error: say why instead.
            if case .failed = error, !(await cli.isOnline()) {
                failure = .offline
            } else {
                failure = .bridge(error)
            }
        } catch {
            Logger.agent.error("Domanda failed: \(error)")
            failure = .unexpected
        }
    }

    /// The bridge to `claude`, started on first use and shared with the Sessioni.
    func readyBridge() async throws -> AgentBridge {
        if let bridge { return bridge }
        guard let claude = await cli.executableURL() else { throw QuestionFailure.claudeMissing }
        // The key is read only once the user chose it, and goes only into the bridge's environment.
        let key = try await usesAPIKey ? apiKey() : nil
        // The HUD's Quota read and a Domanda can both get here across the awaits: keep one bridge.
        if let bridge { return bridge }
        let bridge = AgentBridge(executable: bridgeExecutable, arguments: bridgeArguments,
                                 environment: ChildEnvironment.make(claude: claude, apiKey: key,
                                                                    conversations: try? ConversationStore.defaultFile()),
                                 quota: { [weak self] reported in
                                     guard let self else { return }
                                     quota = quota.merging(reported)
                                 },
                                 remember: { [weak self] text, title in
                                     await self?.remember(text, titled: title) ?? "Bubo non è disponibile."
                                 }) { [index] query, project, source in
            await index?.toolResult(for: query, project: project, source: source) ?? "L'Indice non è disponibile."
        }
        self.bridge = bridge
        return bridge
    }

    /// Saves a note for the `ricorda` tool, and returns what the tool answers `claude`.
    func remember(_ text: String, titled title: String) async -> String {
        do {
            guard let note = try await secondBrain?.remember(text, titled: title) else {
                return "Nota non salvata: l'utente non ha scelto il Secondo cervello. Digli di sceglierlo in "
                    + "Impostazioni › Generale › Secondo cervello."
            }
            savedNote = note.file
            return "Nota salvata nel Secondo cervello: Bubo/Note/\(note.file.lastPathComponent)"
        } catch NoteWriter.Failure.unreachable {
            return "Nota non salvata: la cartella del Secondo cervello non è raggiungibile (disco scollegato o "
                + "cartella spostata)."
        } catch {
            Logger.index.error("Note not saved: \(error)")
            return "Nota non salvata: Bubo non è riuscito a scriverla."
        }
    }

    /// Where Domande run: they have no Progetto, so an empty folder of Bubo's own.
    private static func directory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Bubo/Domande", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
