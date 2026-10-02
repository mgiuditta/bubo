import Foundation
import Testing
@testable import Bubo

/// [Avvia ora] on a fake bridge played by `/bin/sh`.
@MainActor
struct ExecutionRunnerTests {
    let repos: WorktreeManagerTests
    let repo: URL
    let log: URL
    let automations: AutomationStore
    let store: SessionStore
    let runner: ExecutionRunner

    /// A bridge that writes every command to `log`. A turn with nobody in front of it reports the mode `default`, asks
    /// for a permission anyway, and reports a denial of the gate (`rm -rf ~`) and one of `claude` (`npm test`, with its
    /// rule); every turn then ends.
    static func executionBridge(log: URL) -> AgentBridge {
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                case "$line" in
                    *'"type":"ask"'*)
                        id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                        case "$line" in
                            *'"unattended"'*)
                                echo "{\"v\":4,\"type\":\"mode\",\"id\":\"$id\",\"permissionMode\":\"default\"}"
                                echo "{\"v\":4,\"type\":\"permission\",\"id\":\"$id\",\"request\":\"p1\",\"tool\":\"Bash\",\"command\":\"curl x\"}"
                                echo "{\"v\":4,\"type\":\"denial\",\"id\":\"$id\",\"toolUseID\":\"t1\",\"tool\":\"Bash\",\"command\":\"rm -rf ~\",\"suggestions\":[],\"source\":\"gate\"}"
                                echo "{\"v\":4,\"type\":\"denial\",\"id\":\"$id\",\"toolUseID\":\"t2\",\"tool\":\"Bash\",\"command\":\"npm test\",\"agent\":\"revisore\",\"suggestions\":[\"Bash(npm test)\"],\"source\":\"sdk\"}" ;;
                        esac
                        echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _, _ in "" }
    }

    init() throws {
        repos = try WorktreeManagerTests()
        repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        log = repos.base.appending(path: "bridge.log")
        automations = AutomationStore(file: repos.base.appending(path: "Automazioni.json"))
        let bridge = Self.executionBridge(log: log)
        store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager,
                             automations: automations) { bridge }
        runner = ExecutionRunner(automations: automations, sessions: store)
    }

    /// The `ask` commands the bridge received, oldest first.
    private func asks() throws -> [[String: Any]] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
            .filter { $0.contains(#""type":"ask""#) }
            .map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }

    private func addAutomation() -> Automation {
        let automation = Automation(id: UUID(), name: "Test notturni", project: repo, request: "Lancia i test")
        automations.add(automation)
        return automation
    }

    private func waitForTheExecution(of id: Automation.ID) async throws {
        try await SessionTests.wait { automations[id]?.lastExecution.map { $0.outcome != .inCorso } == true }
    }

    // Criterio 1: una Richiesta arrivata lo stesso si nega subito, e l'Esecuzione finisce Ferma.
    @Test(.timeLimit(.minutes(1)))
    func anUnattendedTurnRefusesAStrayPermissionAtOnceAndNeverWaits() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()

        let id = try #require(runner.run(automation.id))
        try await waitForTheExecution(of: automation.id)

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(lines.contains { $0.contains(#""request":"p1""#) && $0.contains(#""behavior":"deny""#) })
        #expect(store.permissions.queues[id]?.isEmpty != false)
        #expect(store.sessions.first { $0.id == id }?.activity == .ferma)
        #expect(automations[automation.id]?.lastExecution?.outcome == .fatta)
        let ask = try #require(try asks().first)
        #expect((ask["unattended"] as? [String: Any])?["rules"] as? [String] == [])
        #expect(ask["permissionMode"] as? String == "auto")
    }

    // Criterio 3: ogni diniego arriva nel resoconto con il suo livello; nessun pulsante per i livelli 4–5.
    @Test(.timeLimit(.minutes(1)))
    func everyGateDenialReachesTheReportWithItsLevel() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()

        let id = try #require(runner.run(automation.id))
        try await waitForTheExecution(of: automation.id)

        let session = try #require(store.sessions.first { $0.id == id })
        #expect(session.denials.map(\.id) == ["t1", "t2"])
        #expect(session.denials[0].level.isDangerous)
        #expect(!session.denials[0].allowsRule)
        #expect(session.denials[0].source == .gate)
        #expect(session.denials[1].allowsRule)
        #expect(session.denials[1].agent == "revisore")
        #expect(automations[automation.id]?.lastExecution?.denialCount == 2)
        #expect(session.automation?.automation == automation.id)
        #expect(session.automation?.name == "Test notturni")
    }

    // Criterio 2: la Regola approvata arriva alla prossima Esecuzione, in un worktree nuovo.
    @Test(.timeLimit(.minutes(1)))
    func theNextExecutionGetsTheAutomationsRulesInANewWorktree() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()
        let first = try #require(runner.run(automation.id))
        try await waitForTheExecution(of: automation.id)
        let denial = try #require(store.sessions.first { $0.id == first }?.denials.last)
        for rule in denial.suggestions { automations.allow(rule, in: automation.id) }

        let second = try #require(runner.run(automation.id))
        try await SessionTests.wait { (try? asks().count) == 2 }
        try await waitForTheExecution(of: automation.id)

        let found = try asks()
        #expect((found[0]["unattended"] as? [String: Any])?["rules"] as? [String] == [])
        #expect((found[1]["unattended"] as? [String: Any])?["rules"] as? [String] == ["Bash(npm test)"])
        #expect(found[0]["cwd"] as? String != found[1]["cwd"] as? String)
        #expect(first != second)
    }

    // Criterio 4: una Sessione normale nello stesso Progetto non ha le Regole dell'Automazione.
    @Test(.timeLimit(.minutes(1)))
    func anotherSessionInTheSameProjectNeverGetsTheAutomationsRules() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()
        automations.allow("Bash(npm test)", in: automation.id)

        try store.start("Ciao", title: "Normale", branch: "bubo/normale", in: repo)
        try await SessionTests.wait { (try? asks().count) == 1 }

        let ask = try #require(try asks().first)
        #expect(ask["unattended"] == nil)
        #expect(!String(describing: ask).contains("npm test"))
    }

    // Criterio 4: rimandata indietro dopo l'Esecuzione, la Sessione lavora con qualcuno davanti.
    @Test(.timeLimit(.minutes(1)))
    func aLaterTurnOfTheExecutionsSessionRunsWithSomeoneThere() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()
        automations.allow("Bash(npm test)", in: automation.id)
        let id = try #require(runner.run(automation.id))
        try await waitForTheExecution(of: automation.id)

        store.sendBack("Ancora", to: id, keepingAcceptedAmong: [])
        try await SessionTests.wait { (try? asks().count) == 2 }

        let later = try asks()[1]
        #expect(later["unattended"] == nil)
        #expect(!String(describing: later).contains("npm test"))
    }

    @Test(.timeLimit(.minutes(1)))
    func theExecutionsModeComesFromInitAndFallsBackToDefault() async throws {
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let automation = addAutomation()

        let id = try #require(runner.run(automation.id))
        try await waitForTheExecution(of: automation.id)

        let session = try #require(store.sessions.first { $0.id == id })
        #expect(session.permissionMode == .autonomous)
        #expect(session.effectiveMode == "default")
    }

    @Test func thePromptCarriesTheRequestAndTheAutomationsName() {
        let automation = Automation(id: UUID(), name: "Test notturni", project: repo, request: "Lancia i test")
        let prompt = ExecutionRunner.prompt(for: automation, scheduledAt: .now, startedAt: .now)
        #expect(prompt.hasPrefix("Lancia i test\n"))
        #expect(prompt.contains("Test notturni"))
    }
}
