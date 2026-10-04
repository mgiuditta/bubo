import Foundation
import Testing
@testable import Bubo

/// The outcomes of the Esecuzioni, on a fake bridge played by `/bin/sh`.
@MainActor
struct ExecutionOutcomeTests {
    let repos: WorktreeManagerTests
    let repo: URL
    let automations: AutomationStore
    let store: SessionStore
    let runner: ExecutionRunner

    /// A bridge whose every turn says only `last` and ends with no denials; with `writing`, it first writes a file
    /// in the folder it works in.
    static func quietBridge(saying last: String, writing: Bool = false) -> AgentBridge {
        let script = #"""
            while read line; do
                case "$line" in
                    *'"type":"ask"'*)
                        id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                        if [ "$2" = write ]; then
                            cwd=$(echo "$line" | sed 's/.*"cwd":"\([^"]*\)".*/\1/' | sed 's#\\/#/#g')
                            echo ciao > "$cwd/nuovo.txt"
                        fi
                        echo "{\"v\":4,\"type\":\"summary\",\"id\":\"$id\",\"text\":\"$1\"}"
                        echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", last, writing ? "write" : "-"],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _, _ in "" }
    }

    init(saying last: String = ExecutionRunner.nothingToReport, writing: Bool = false) throws {
        repos = try WorktreeManagerTests()
        repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        automations = AutomationStore()
        let bridge = Self.quietBridge(saying: last, writing: writing)
        store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager,
                             automations: automations) { bridge }
        runner = ExecutionRunner(automations: automations, sessions: store)
    }

    private func addAutomation(named name: String = "Controllo", in project: URL? = nil) -> Automation {
        let automation = Automation(id: UUID(), name: name, project: project ?? repo, request: "Controlla")
        automations.add(automation)
        return automation
    }

    private func waitForTheExecution(of id: Automation.ID) async throws {
        try await SessionTests.wait { automations[id]?.lastExecution.map { $0.outcome != .inCorso } == true }
    }

    // Criterio 2: Senza modifiche → Sessione archiviata, worktree assente.
    @Test(.timeLimit(.minutes(1)))
    func anExecutionWithNothingToReportIsArchivedWithoutItsWorktree() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()

        let id = try #require(runner.run(automation.id))
        try await waitForTheExecution(of: automation.id)

        let session = try #require(store.sessions.first { $0.id == id })
        let folder = try #require(session.workspace?.folder)
        #expect(automations[automation.id]?.lastExecution?.outcome == .senzaModifiche)
        #expect(session.phase == .archiviata)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        let worktrees = try repos.git("worktree", "list", in: repo)
        #expect(!worktrees.contains(folder.lastPathComponent))
    }

    @Test(.timeLimit(.minutes(1)))
    func anExecutionThatLeftChangesIsDoneAndKeepsItsWorktree() async throws {
        let outcomes = try ExecutionOutcomeTests(writing: true)
        defer {
            try? FileManager.default.removeItem(at: outcomes.repos.base)
            try? FileManager.default.removeItem(at: repos.base)
        }
        let automation = outcomes.addAutomation()

        let id = try #require(outcomes.runner.run(automation.id))
        try await outcomes.waitForTheExecution(of: automation.id)

        let session = try #require(outcomes.store.sessions.first { $0.id == id })
        let folder = try #require(session.workspace?.folder)
        #expect(outcomes.automations[automation.id]?.lastExecution?.outcome == .fatta)
        #expect(session.phase == .aperta)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "nuovo.txt").path))
    }

    @Test(.timeLimit(.minutes(1)))
    func anExecutionWithAnotherMessageIsDone() async throws {
        let outcomes = try ExecutionOutcomeTests(saying: "Ho aggiornato le dipendenze.")
        defer {
            try? FileManager.default.removeItem(at: outcomes.repos.base)
            try? FileManager.default.removeItem(at: repos.base)
        }
        let automation = outcomes.addAutomation()

        let id = try #require(outcomes.runner.run(automation.id))
        try await outcomes.waitForTheExecution(of: automation.id)

        #expect(outcomes.automations[automation.id]?.lastExecution?.outcome == .fatta)
        #expect(outcomes.store.sessions.first { $0.id == id }?.phase == .aperta)
    }

    // Criterio 3: la stessa Automazione ancora al lavoro → riga Saltata (sovrapposta).
    @Test(.timeLimit(.minutes(1)))
    func theSameAutomationStillAtWorkIsSkippedAsOverlapping() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()
        let first = try #require(runner.run(automation.id))

        #expect(runner.run(automation.id, scheduledAt: .now) == nil)

        let skipped = try #require(automations[automation.id]?.executions.last)
        #expect(skipped.outcome == .saltata)
        #expect(skipped.skipReason == .sovrapposta)
        #expect(skipped.session == nil)
        try await SessionTests.wait { automations[automation.id]?.executions.first?.outcome != .inCorso }
        #expect(automations[automation.id]?.executions.first?.session == first)
        #expect(store.sessions.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func differentAutomationsStartTogether() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let one = addAutomation(named: "Uno")
        let other = addAutomation(named: "Due")

        #expect(runner.run(one.id) != nil)
        #expect(runner.run(other.id) != nil)

        try await waitForTheExecution(of: one.id)
        try await waitForTheExecution(of: other.id)
        #expect(store.sessions.count == 2)
        #expect(automations[one.id]?.lastExecution?.outcome == .senzaModifiche)
        #expect(automations[other.id]?.lastExecution?.outcome == .senzaModifiche)
    }

    // Criterio 4: Progetto non git con un'altra Sessione al lavoro → Saltata (sovrapposta).
    @Test(.timeLimit(.minutes(1)))
    func outsideGitAnotherSessionAtWorkMakesItOverlapping() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let folder = repos.base.appending(path: "cartella", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let automation = addAutomation(in: folder)
        try store.start("Ciao", title: "Normale", branch: "bubo/normale", in: folder)

        #expect(runner.run(automation.id, scheduledAt: .now) == nil)

        #expect(automations[automation.id]?.lastExecution?.skipReason == .sovrapposta)
        try await SessionTests.wait { store.sessions.allSatisfy { !$0.isRunning } }
    }

    @Test(.timeLimit(.minutes(1)))
    func inGitAnotherSessionAtWorkDoesNotOverlap() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()
        try store.start("Ciao", title: "Normale", branch: "bubo/normale", in: repo)

        #expect(runner.run(automation.id) != nil)

        try await waitForTheExecution(of: automation.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func anExecutionLeftInCorsoByQuittingBecomesInterrupted() throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()
        automations.record(Execution(startedAt: .now, session: UUID(), outcome: .inCorso), for: automation.id)

        runner.markInterrupted()

        #expect(automations[automation.id]?.lastExecution?.outcome == .interrotta)
    }

    @Test func thePromptCarriesBothTimesAndAsksForTheFixedPhrase() {
        let automation = Automation(id: UUID(), name: "Controllo", project: repo, request: "Controlla")
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let started = due.addingTimeInterval(3 * 60 * 60)
        let time = Date.FormatStyle(date: .abbreviated, time: .shortened)

        let prompt = ExecutionRunner.prompt(for: automation, scheduledAt: due, startedAt: started)

        #expect(prompt.contains(due.formatted(time)))
        #expect(prompt.contains(started.formatted(time)))
        #expect(prompt.contains(ExecutionRunner.nothingToReport))
        try? FileManager.default.removeItem(at: repos.base)
    }
}
