import Foundation
import Testing
@testable import Bubo

/// Where the result of an Esecuzione lands: Da guardare on the Board and a notification with its outcome and denials
/// (spec 19, #171), on fake bridges played by `/bin/sh`.
@MainActor
struct ExecutionResultTests {
    let repos: WorktreeManagerTests
    let repo: URL
    let automations: AutomationStore
    let store: SessionStore
    let runner: ExecutionRunner
    /// The Esecuzioni `onFinish` reported, oldest first.
    let finished = Finished()

    /// What `onFinish` received.
    @MainActor
    final class Finished {
        var executions: [Execution] = []
    }

    init(bridge: AgentBridge? = nil) throws {
        repos = try WorktreeManagerTests()
        repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        automations = AutomationStore()
        let bridge = bridge ?? ExecutionRunnerTests.executionBridge(log: repos.base.appending(path: "bridge.log"))
        store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager,
                             automations: automations) { bridge }
        runner = ExecutionRunner(automations: automations, sessions: store)
        runner.onFinish = { [finished] _, execution in finished.executions.append(execution) }
    }

    private func runAndWait() async throws -> (automation: Automation.ID, session: UUID) {
        let automation = Automation(id: UUID(), name: "Test notturni", project: repo, request: "Lancia i test")
        automations.add(automation)
        let session = try #require(runner.run(automation.id))
        try await SessionTests.wait { finished.executions.count == 1 }
        return (automation.id, session)
    }

    // Criterio 1: Esecuzione Fatta → card in Da guardare con il segno Automazione.
    @Test(.timeLimit(.minutes(1)))
    func aDoneExecutionWaitsInDaGuardareWithItsMark() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let (automation, id) = try await runAndWait()

        let session = try #require(store.sessions.first { $0.id == id })
        #expect(automations[automation]?.lastExecution?.outcome == .fatta)
        #expect(BoardColumn(session, at: .now) == .daGuardare)
        #expect(session.automation?.automation == automation)
        #expect(session.automation?.name == "Test notturni")
    }

    // Criterio 2: notifica con esito e numero di dinieghi.
    @Test(.timeLimit(.minutes(1)))
    func aDoneExecutionIsAnnouncedWithItsDenials() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let (_, id) = try await runAndWait()

        let execution = try #require(finished.executions.first)
        #expect(execution.outcome == .fatta)
        #expect(execution.session == id)
        #expect(execution.denialCount == 2)
        let notice = try #require(execution.resultNotice)
        #expect(notice.contains("2"))
    }

    // Criterio 2: nessuna notifica per Senza modifiche.
    @Test(.timeLimit(.minutes(1)))
    func anExecutionWithNothingToReportIsNotAnnounced() async throws {
        let quiet = try ExecutionResultTests(bridge: ExecutionOutcomeTests.quietBridge(saying: ExecutionRunner.nothingToReport))
        defer {
            try? FileManager.default.removeItem(at: quiet.repos.base)
            try? FileManager.default.removeItem(at: repos.base)
        }
        _ = try await quiet.runAndWait()

        let execution = try #require(quiet.finished.executions.first)
        #expect(execution.outcome == .senzaModifiche)
        #expect(execution.resultNotice == nil)
    }

    @Test(arguments: [Execution.Outcome.inCorso, .senzaModifiche, .saltata, .interrotta])
    func onlyAnEndWithSomethingToLookAtIsAnnounced(outcome: Execution.Outcome) throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        #expect(Execution(startedAt: .now, outcome: outcome).resultNotice == nil)
        #expect(Execution(startedAt: .now, outcome: .errore, denialCount: 1).resultNotice != nil)
    }
}
