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

    /// Creates a model that finds `claude` with `cli`.
    init(cli: ClaudeCLI = ClaudeCLI()) {
        self.cli = cli
    }

    @ObservationIgnored private let cli: ClaudeCLI
    @ObservationIgnored private var bridge: AgentBridge?
    @ObservationIgnored private var lastPrompt = ""
    @ObservationIgnored private var answering: Task<Void, Never>?

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

    /// Stops the answer in progress, keeping what arrived.
    func stop() {
        answering?.cancel()
    }

    private func start(_ text: String) {
        answering?.cancel()
        answer = ""
        failure = nil
        isAnswering = true
        answering = Task { await stream(text) }
    }

    private func stream(_ text: String) async {
        defer { isAnswering = false }
        let signpostID = Signposts.signposter.makeSignpostID()
        var waitingForFirstToken: OSSignpostIntervalState? =
            Signposts.signposter.beginInterval("Domanda, primo token", id: signpostID)
        defer { waitingForFirstToken.map { Signposts.signposter.endInterval("Domanda, primo token", $0) } }
        do {
            let bridge = try await readyBridge()
            for try await chunk in bridge.ask(text, in: try Self.directory()) {
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
            failure = .bridge(error)
        } catch {
            Logger.agent.error("Domanda failed: \(error)")
            failure = .unexpected
        }
    }

    private func readyBridge() async throws -> AgentBridge {
        if let bridge { return bridge }
        guard let claude = await cli.executableURL() else { throw QuestionFailure.claudeMissing }
        let bridge = AgentBridge(executable: Bundle.main.bundleURL.appending(path: "Contents/Helpers/bubo-agent"),
                                 environment: ChildEnvironment.make(claude: claude))
        self.bridge = bridge
        return bridge
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
