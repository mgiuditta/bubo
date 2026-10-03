import Foundation
import Testing
@testable import Bubo

/// The engine and model of a Sessione: Claude or Copilot, chosen in ⌘N, in the Bozza and per Progetto (ADR 0012).
struct EngineChoiceTests {
    private let models = [
        CopilotModel(id: "opus-c", name: "Claude Opus", multiplier: 3, supportedEfforts: [.high, .low]),
        CopilotModel(id: "mini", name: "GPT Mini", multiplier: 0),
        CopilotModel(id: "gpt", name: "GPT", multiplier: 1, supportedEfforts: [.medium]),
    ]

    @Test func theScalaOfCopilotGoesByCreditsThenEffort() {
        #expect(CopilotStep.scala(of: models) == [
            CopilotStep(model: "mini", modelName: "GPT Mini", effort: nil),
            CopilotStep(model: "gpt", modelName: "GPT", effort: .medium),
            CopilotStep(model: "opus-c", modelName: "Claude Opus", effort: .low),
            CopilotStep(model: "opus-c", modelName: "Claude Opus", effort: .high),
        ])
    }

    @Test func strongerClimbsTheScalaOfTheSessionesEngine() {
        let gpt = EngineChoice(engine: .copilot, copilotModel: CopilotStep(model: "gpt", modelName: "GPT", effort: .medium))
        #expect(gpt.stronger(copilotModels: models)?.copilotModel
            == CopilotStep(model: "opus-c", modelName: "Claude Opus", effort: .low))
        let top = EngineChoice(engine: .copilot,
                               copilotModel: CopilotStep(model: "opus-c", modelName: "Claude Opus", effort: .high))
        #expect(top.stronger(copilotModels: models) == nil)
        let sonnet = EngineChoice(engine: .claude, claudeModel: Scala.Step(family: .sonnet, effort: .high))
        #expect(sonnet.stronger(copilotModels: models)?.claudeModel == Scala.Step(family: .opus, effort: .medium))
        #expect(EngineChoice.claude.stronger(copilotModels: models) == nil)
    }

    @Test func theNameSaysEngineAndModel() {
        #expect(EngineChoice.claude.name.hasPrefix("Claude · "))
        let gpt = EngineChoice(engine: .copilot, copilotModel: CopilotStep(model: "gpt", modelName: "GPT", effort: nil))
        #expect(gpt.name == "Copilot · GPT")
    }

    @Test func aProjectKeepsItsChoiceAndClaudeIsTheDefault() throws {
        let suite = "EngineChoiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = URL(filePath: "/tmp/repo")
        let gpt = EngineChoice(engine: .copilot, copilotModel: CopilotStep(model: "gpt", modelName: "GPT", effort: .medium))
        #expect(ProjectEngineStore(defaults: defaults).choice(for: project) == .claude)
        ProjectEngineStore(defaults: defaults).setChoice(gpt, for: project)
        #expect(ProjectEngineStore(defaults: defaults).choice(for: project) == gpt)
        #expect(ProjectEngineStore(defaults: defaults).choice(for: URL(filePath: "/tmp/altro")) == .claude)
    }

    @Test func sessionesAndBozzeSavedBeforeTheChoiceStayOnClaude() throws {
        let session = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Vecchia","project":"file:///tmp/repo","activity":"ferma"}"#
        #expect(try JSONDecoder().decode(Session.self, from: Data(session.utf8)).choice == .claude)
        let draft = try JSONEncoder().encode(Draft(title: "Bozza", text: "", project: URL(filePath: "/tmp/repo")))
        #expect(try JSONDecoder().decode(Draft.self, from: draft).choice == nil)
    }

    @Test func theChoiceOfASessioneIsKept() throws {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp/repo"))
        let gpt = EngineChoice(engine: .copilot, copilotModel: CopilotStep(model: "gpt", modelName: "GPT", effort: .high))
        session.choice = gpt
        #expect(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)).choice == gpt)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aSessioneStartsOnItsProjectsCopilotModel() async throws {
        let repos = try WorktreeManagerTests()
        let repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        let log = repos.base.appending(path: "bridge.log")
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let suite = "EngineChoiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                case "$line" in
                    *'"type":"copilot"'*)
                        id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                        echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        let bridge = AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                                 environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _, _ in "" }
        let store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager,
                                 sandbox: SandboxStore(defaults: defaults)) { bridge }
        store.engines = ProjectEngineStore(defaults: defaults)
        store.locateCopilot = { URL(filePath: "/opt/homebrew/bin/copilot") }
        store.copilotConsents = { [EndpointSettings.copilotConsentID] }
        let gpt = EngineChoice(engine: .copilot, copilotModel: CopilotStep(model: "gpt", modelName: "GPT", effort: .high))
        store.engines.setChoice(gpt, for: repo)

        try store.start("Pulisci", title: "Prova", branch: "bubo/prova", in: repo)
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }

        #expect(store.sessions.first?.choice == gpt)
        let asked = try String(contentsOf: log, encoding: .utf8)
        #expect(asked.contains(#""model":"gpt""#))
        #expect(asked.contains(#""effort":"high""#))
        #expect(!asked.contains(#""type":"ask""#))
    }

    @MainActor
    @Test func copilotModelsAreEmptyWithoutCopilot() async throws {
        let repos = try WorktreeManagerTests()
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager) {
            throw CancellationError()
        }
        store.locateCopilot = { nil }
        await store.loadCopilotModels()
        #expect(store.copilotModels == [])
    }
}
