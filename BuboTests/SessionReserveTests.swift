import Foundation
import Testing
@testable import Bubo

/// #727: a Sessione stopped for Quota or a limit offers «Continua con …» on the Riserva, in a new Sessione (ADR 0014).
/// The bridge is played by `/bin/sh`: no paid turn.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SessionReserveTests {
    let file = URL.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
    let suite = "SessionReserveTests-\(UUID().uuidString)"

    /// A bridge that answers by the prompt: «Limite» stops at Claude's limit, «Crediti» at Copilot's, «Rete» fails
    /// with a generic error, any other ends.
    static func bridge() -> AgentBridge {
        let script = #"""
            while read -r line; do
              case "$line" in *'"type":"ask"'*|*'"type":"copilot"'*) ;; *) continue ;; esac
              id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
              case "$line" in
                *'"prompt":"Limite"'*) echo "{\"v\":4,\"type\":\"limit\",\"id\":\"$id\"}" ;;
                *'"prompt":"Crediti"'*) echo "{\"v\":4,\"type\":\"copilotLimit\",\"id\":\"$id\",\"message\":\"Crediti finiti\"}" ;;
                *'"prompt":"Rete"'*) echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"fetch failed\"}" ;;
                *) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
              esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                           environment: ["PATH": "/usr/bin:/bin"]) { _, _, _ in "" }
    }

    /// A store with both Motori ready and the Riserva `hasReserve`, and the Sandbox on where `isSandboxed`.
    func store(hasReserve: Bool = true, isSandboxed: Bool = false, project: URL) throws -> SessionStore {
        let sandbox = SandboxStore(defaults: try #require(UserDefaults(suiteName: suite)))
        if isSandboxed { sandbox.setEnabled(true, in: project) }
        let bridge = Self.bridge()
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: URL.temporaryDirectory),
                                 sandbox: sandbox) { bridge }
        store.primaryEngine = { PrimaryEngine(engine: .claude, hasReserve: hasReserve) }
        store.locateClaude = { URL(filePath: "/c") }
        store.locateCopilot = { URL(filePath: "/c") }
        store.copilotConsents = { [EndpointSettings.copilotConsentID] }
        return store
    }

    func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "progetto-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The Sessione `prompt` started on `engine` in `store`, once its turn ended in Errore.
    func stopped(_ prompt: String, on engine: Session.Engine, in store: SessionStore,
                 project: URL) async throws -> Session {
        let id = try store.start(prompt, title: "Prova", branch: "", in: project, onCheckout: true,
                                 choice: EngineChoice(engine: engine))
        try await SessionTests.wait { store.sessions.first { $0.id == id }?.activity == .errore }
        return try #require(store.sessions.first { $0.id == id })
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: file)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test(arguments: [(Session.Engine.claude, "Limite", Session.Engine.copilot),
                      (Session.Engine.copilot, "Crediti", Session.Engine.claude)])
    func aSessioneStoppedForItsLimitOffersTheOtherMotore(engine: Session.Engine, prompt: String,
                                                         reserve: Session.Engine) async throws {
        defer { cleanUp() }
        let project = try folder()
        let session = try await stopped(prompt, on: engine, in: try store(project: project), project: project)

        #expect(session.reserve == reserve)
    }

    @Test func aNetworkErrorOffersNoReserve() async throws {
        defer { cleanUp() }
        let project = try folder()
        let session = try await stopped("Rete", on: .claude, in: try store(project: project), project: project)

        #expect(session.failure == "fetch failed")
        #expect(session.reserve == nil)
    }

    @Test func withoutTheRiservaALimitOffersNothing() async throws {
        defer { cleanUp() }
        let project = try folder()
        let session = try await stopped("Limite", on: .claude, in: try store(hasReserve: false, project: project),
                                        project: project)

        #expect(session.reserve == nil)
    }

    @Test func withoutCopilotReadyALimitOfClaudeOffersNothing() async throws {
        defer { cleanUp() }
        let project = try folder()
        let store = try store(project: project)
        store.locateCopilot = { nil }
        let session = try await stopped("Limite", on: .claude, in: store, project: project)

        #expect(session.reserve == nil)
    }

    // Copilot has no Sandbox: a Sessione with the Sandbox on never continues there.
    @Test(.enabled(if: ReleaseArea.sandbox.isAvailable()))
    func withTheSandboxOnALimitOfClaudeOffersNoCopilot() async throws {
        defer { cleanUp() }
        let project = try folder()
        let session = try await stopped("Limite", on: .claude, in: try store(isSandboxed: true, project: project),
                                        project: project)

        #expect(session.reserve == nil)
    }

    @Test func continuingOpensANewSessioneOnTheRiservaWithThePromptAndTheSummary() async throws {
        defer { cleanUp() }
        let project = try folder()
        let store = try store(project: project)
        store.summary = { _ in SessionSummary(done: ["Letto il codice del login"]) }
        let stopped = try await stopped("Limite", on: .claude, in: store, project: project)

        let id = try #require(await store.continueOnReserve(stopped.id))

        let continued = try #require(store.sessions.first { $0.id == id })
        #expect(continued.engine == .copilot)
        #expect(continued.project == project)
        #expect(continued.title == stopped.title)
        let prompt = try #require(continued.prompt)
        #expect(prompt.contains("Letto il codice del login"))
        #expect(prompt.hasSuffix("Limite"))
        // The stopped Sessione stays, without the offer.
        let previous = try #require(store.sessions.first { $0.id == stopped.id })
        #expect(previous.activity == .errore)
        #expect(previous.reserve == nil)
        #expect(await store.continueOnReserve(stopped.id) == nil)
    }
}
