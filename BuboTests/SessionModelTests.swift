import Foundation
import Testing
@testable import Bubo

/// The model · sforzo chosen in a Sessione: it holds from the next turn, without restarting the Sessione (spec 10).
struct SessionModelTests {
    @Test func aSessioneSavedBeforeTheChoiceTakesClaudesModel() throws {
        let saved = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Vecchia","project":"file:///tmp/repo","activity":"ferma"}"#
        #expect(try JSONDecoder().decode(Session.self, from: Data(saved.utf8)).model == nil)
    }

    @Test func theChoiceIsKept() throws {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp/repo"))
        session.model = Scala.Step(family: .opus, effort: .high)
        let saved = try JSONEncoder().encode(session)
        #expect(try JSONDecoder().decode(Session.self, from: saved).model == Scala.Step(family: .opus, effort: .high))
    }

    @Test func aStepIsNamedWithItsEffort() {
        #expect(Scala.Step(family: .haiku, effort: nil).name == "Haiku")
        #expect(Scala.Step(family: .sonnet, effort: .medium).name.hasPrefix("Sonnet · "))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func theNextTurnRunsOnTheChosenModelWithoutRestarting() async throws {
        let repos = try WorktreeManagerTests()
        let repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        let log = repos.base.appending(path: "bridge.log")
        let file = repos.base.appending(path: "Sessioni.json")
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let suite = "SessionModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = SandboxGateTests.gateBridge(log: log)
        let store = SessionStore(file: file, worktrees: repos.manager, sandbox: SandboxStore(defaults: defaults)) { bridge }

        try store.start("Pulisci", title: "Prova", branch: "bubo/prova", in: repo)
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }
        let id = try #require(store.sessions.first?.id)
        store.setChoice(EngineChoice(engine: .claude, claudeModel: Scala.Step(family: .opus, effort: .high)), in: id)
        store.sendBack("Ancora", to: id, keepingAcceptedAmong: [])
        try await SessionTests.wait { store.sessions.first?.activity == .ferma && store.sessions.first?.summary == nil }
        try await SessionTests.wait {
            (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").filter { $0.contains(#""type":"ask""#) }.count == 2
        }

        let asks = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
            .filter { $0.contains(#""type":"ask""#) }
        let first = try #require(asks.first), second = try #require(asks.last)
        #expect(!first.contains(#""model""#))
        #expect(!first.contains(#""effort""#))
        #expect(second.contains(#""model":"opus""#))
        #expect(second.contains(#""effort":"high""#))
        #expect(store.sessions.count == 1)
    }
}
