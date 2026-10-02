import Foundation
import Testing
@testable import Bubo

/// The recovery of the missed times, the Mac's sleep and "Tieni sveglio il Mac", on a fake clock and a simulated sleep.
@MainActor
struct AutomationRecoveryTests {
    let repos: WorktreeManagerTests
    let repo: URL
    let automations: AutomationStore
    let store: SessionStore
    let runner: ExecutionRunner
    let clock: AutomationSchedulerTests.Clock
    let scheduler: AutomationScheduler
    let defaults: UserDefaults
    let suite = "AutomationRecoveryTests-\(UUID().uuidString)"
    /// The times the recovery announced, by Automazione.
    let recoveries = Recoveries()

    final class Recoveries {
        var announced: [(Automation.ID, Date)] = []
    }

    /// A bridge whose turns never end by themselves: only the cancel of their turn ends them.
    static let endlessBridge: AgentBridge = {
        let script = #"""
            while read line; do
                case "$line" in
                    *'"type":"cancel"'*)
                        id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                        echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _, _ in "" }
    }()

    init() throws {
        try self.init(bridge: ExecutionOutcomeTests.quietBridge(saying: ExecutionRunner.nothingToReport))
    }

    init(bridge: AgentBridge) throws {
        repos = try WorktreeManagerTests()
        repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        automations = AutomationStore()
        store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager,
                             automations: automations) { bridge }
        runner = ExecutionRunner(automations: automations, sessions: store)
        let clock = try AutomationSchedulerTests.Clock("2026-10-02T08:30:00+02:00")
        self.clock = clock
        defaults = try #require(UserDefaults(suiteName: suite))
        scheduler = AutomationScheduler(automations: automations, runner: runner, calendar: { clock.calendar },
                                        now: { clock.now }, defaults: defaults)
        scheduler.onRecovery = { [recoveries] automation, scheduledAt in
            recoveries.announced.append((automation.id, scheduledAt))
        }
    }

    private func cleanUp() {
        scheduler.keepAwake.release()
        try? FileManager.default.removeItem(at: repos.base)
        defaults.removePersistentDomain(forName: suite)
    }

    private func addAutomation(_ recurrence: Recurrence?, named name: String = "Controllo") -> Automation {
        let automation = Automation(id: UUID(), name: name, project: repo, request: "Controlla", recurrence: recurrence)
        automations.add(automation)
        return automation
    }

    private func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    private func waitForTheEnd(of id: Automation.ID) async throws {
        try await SessionTests.wait { automations[id]?.lastExecution.map { $0.outcome != .inCorso } == true }
    }

    // Criterio 1: sonno di 3 giorni → una riga per ogni orario perso, un solo recupero, partito entro 5 s.
    @Test(.timeLimit(.minutes(1)))
    func aSleepOfThreeDaysLeavesARowForEachMissedTimeAndOneRecovery() async throws {
        defer { cleanUp() }
        let automation = addAutomation(.daily(hour: 9, minute: 0))
        scheduler.start()

        scheduler.sleep()
        clock.now = try date("2026-10-05T10:00:00+02:00")
        let elapsed = ContinuousClock().measure { scheduler.wake() }

        let executions = try #require(automations[automation.id]?.executions)
        let skipped = executions.filter { $0.outcome == .saltata }
        #expect(skipped.map(\.scheduledAt) == [try date("2026-10-02T09:00:00+02:00"),
                                               try date("2026-10-03T09:00:00+02:00"),
                                               try date("2026-10-04T09:00:00+02:00")])
        #expect(skipped.allSatisfy { $0.skipReason == .assente })
        let recovery = try #require(executions.last)
        #expect(recovery.outcome == .inCorso)
        #expect(recovery.scheduledAt == (try date("2026-10-05T09:00:00+02:00")))
        #expect(recovery.startedAt == clock.now)
        #expect(elapsed < .seconds(5))
        #expect(recoveries.announced.count == 1)
        #expect(scheduler.plan[automation.id] == (try date("2026-10-06T09:00:00+02:00")))

        // Another waking recovers nothing more.
        scheduler.wake()
        #expect(automations[automation.id]?.executions.count == 4)
        try await waitForTheEnd(of: automation.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func reopeningBuboRecoversTheTimesMissedWhileItWasClosed() async throws {
        defer { cleanUp() }
        let automation = addAutomation(.hourly(minute: 0))
        scheduler.start()

        // Bubo closed at 08:30, opened again at 11:10.
        clock.now = try date("2026-10-02T11:10:00+02:00")
        let reopened = AutomationScheduler(automations: automations, runner: runner, calendar: { clock.calendar },
                                           now: { clock.now }, defaults: defaults)
        reopened.start()

        let executions = try #require(automations[automation.id]?.executions)
        #expect(executions.map(\.scheduledAt) == [try date("2026-10-02T09:00:00+02:00"),
                                                  try date("2026-10-02T10:00:00+02:00"),
                                                  try date("2026-10-02T11:00:00+02:00")])
        #expect(executions.map(\.outcome) == [.saltata, .saltata, .inCorso])
        try await waitForTheEnd(of: automation.id)
    }

    @Test func aPausedAutomationRecoversNothingAndRecordsNothing() throws {
        defer { cleanUp() }
        let automation = addAutomation(.daily(hour: 9, minute: 0))
        automations.pause(automation.id)
        scheduler.start()

        scheduler.sleep()
        clock.now = try date("2026-10-05T10:00:00+02:00")
        scheduler.wake()

        #expect(automations[automation.id]?.executions.isEmpty == true)
        #expect(recoveries.announced.isEmpty)
    }

    @Test func aTimeOlderThanSevenDaysIsNotRecorded() throws {
        defer { cleanUp() }
        let automation = addAutomation(.daily(hour: 9, minute: 0))
        scheduler.start()

        scheduler.sleep()
        clock.now = try date("2026-10-22T08:00:00+02:00")
        scheduler.wake()

        let executions = try #require(automations[automation.id]?.executions)
        #expect(executions.count == 7)
        #expect(executions.first?.scheduledAt == (try date("2026-10-15T09:00:00+02:00")))
        #expect(executions.last?.scheduledAt == (try date("2026-10-21T09:00:00+02:00")))
    }

    @Test func theFirstLaunchHasNothingToRecover() throws {
        defer { cleanUp() }
        let automation = addAutomation(.daily(hour: 9, minute: 0))
        clock.now = try date("2026-10-05T10:00:00+02:00")

        scheduler.start()

        #expect(automations[automation.id]?.executions.isEmpty == true)
    }

    // Criterio 4: asserzioni sempre rilasciate a fine Esecuzione o al sonno.
    @Test(.timeLimit(.minutes(1)))
    func anExecutionHoldsItsActivityUntilItEnds() async throws {
        defer { cleanUp() }
        let automation = addAutomation(nil)

        runner.run(automation.id)
        #expect(runner.heldActivities == 1)
        try await waitForTheEnd(of: automation.id)

        #expect(runner.heldActivities == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func sleepingInterruptsTheExecutionAndReleasesItsActivity() async throws {
        let recovery = try AutomationRecoveryTests(bridge: Self.endlessBridge)
        defer { recovery.cleanUp() }
        let automation = recovery.addAutomation(nil)
        recovery.scheduler.start()
        let id = try #require(recovery.runner.run(automation.id))
        #expect(recovery.runner.heldActivities == 1)

        recovery.scheduler.sleep()

        #expect(recovery.runner.heldActivities == 0)
        #expect(recovery.automations[automation.id]?.lastExecution?.outcome == .interrotta)
        try await SessionTests.wait {
            recovery.store.sessions.first { $0.id == id }.map { !$0.isRunning && $0.isInterrupted } == true
        }
        let session = try #require(recovery.store.sessions.first { $0.id == id })
        #expect(session.activity == .ferma)
        #expect(session.isInterrupted)
        // The end of its turn keeps it Interrotta, never in corso.
        try await Task.sleep(for: .milliseconds(200))
        #expect(recovery.automations[automation.id]?.lastExecution?.outcome == .interrotta)
    }

    @Test func theMacStaysAwakeOnlyWithTheSwitchOnAndAnAutomationWithinTwoHours() throws {
        defer { cleanUp() }
        _ = addAutomation(.daily(hour: 12, minute: 0))
        defaults.set(true, forKey: KeepAwake.defaultsKey)

        // At 08:30 the 12:00 is three hours and a half away.
        scheduler.start()
        #expect(!scheduler.keepAwake.isHeld)

        clock.now = try date("2026-10-02T10:30:00+02:00")
        scheduler.reschedule()
        #expect(scheduler.keepAwake.isHeld)

        scheduler.sleep()
        #expect(!scheduler.keepAwake.isHeld)

        defaults.set(false, forKey: KeepAwake.defaultsKey)
        scheduler.wake()
        #expect(!scheduler.keepAwake.isHeld)
    }

    // Criterio 2: dopo 7 giorni di Esecuzioni finte, 0 worktree orfani.
    @Test(.timeLimit(.minutes(2)))
    func aWeekOfExecutionsLeavesNoOrphanWorktree() async throws {
        defer { cleanUp() }
        let automation = addAutomation(.daily(hour: 9, minute: 0))
        let start = try date("2026-10-02T09:00:00+02:00")
        for day in 0..<7 {
            let time = start.addingTimeInterval(TimeInterval(day * 24 * 60 * 60))
            runner.run(automation.id, scheduledAt: time, at: time)
            try await waitForTheEnd(of: automation.id)
        }
        // A crash cut the last archive short: its worktree is back where it was.
        let last = try #require(automations[automation.id]?.lastExecution?.session)
        let workspace = try #require(store.sessions.first { $0.id == last }?.workspace)
        let branch = try #require(workspace.branch)
        _ = try repos.git("worktree", "add", "-q", "-b", branch, workspace.folder.path, in: repo)

        let removed = await WorktreeSweeper(automations: automations, sessions: store).sweep()

        #expect(removed == 1)
        let worktrees = try repos.git("worktree", "list", in: repo).split(separator: "\n")
        #expect(worktrees.count == 1)
        #expect(automations[automation.id]?.executions.allSatisfy { $0.outcome == .senzaModifiche } == true)
    }
}
