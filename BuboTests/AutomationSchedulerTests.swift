import Foundation
import Testing
@testable import Bubo

/// The timer of the Ripetizioni, on a fake clock.
@MainActor
struct AutomationSchedulerTests {
    /// The time and the time zone the scheduler reads.
    final class Clock {
        var now: Date
        var calendar: Calendar

        init(_ now: String, zone: String = "Europe/Rome") throws {
            self.now = try Date(now, strategy: .iso8601)
            calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
        }
    }

    let repos: WorktreeManagerTests
    let repo: URL
    let automations: AutomationStore
    let store: SessionStore
    let clock: Clock
    let scheduler: AutomationScheduler
    /// Where the scheduler keeps when it last watched: never the user's own.
    let defaults: UserDefaults
    let suite = "AutomationSchedulerTests-\(UUID().uuidString)"

    init() throws {
        repos = try WorktreeManagerTests()
        repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        automations = AutomationStore()
        let bridge = ExecutionOutcomeTests.quietBridge(saying: ExecutionRunner.nothingToReport)
        store = SessionStore(file: repos.base.appending(path: "Sessioni.json"), worktrees: repos.manager,
                             automations: automations) { bridge }
        let clock = try Clock("2026-10-02T08:30:00+02:00")
        self.clock = clock
        defaults = try #require(UserDefaults(suiteName: suite))
        scheduler = AutomationScheduler(automations: automations,
                                        runner: ExecutionRunner(automations: automations, sessions: store),
                                        calendar: { clock.calendar }, now: { clock.now }, defaults: defaults)
    }

    private func addAutomation(_ recurrence: Recurrence?, named name: String = "Controllo",
                               in project: URL? = nil) -> Automation {
        let automation = Automation(id: UUID(), name: name, project: project ?? repo, request: "Controlla",
                                    recurrence: recurrence)
        automations.add(automation)
        return automation
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: repos.base)
        defaults.removePersistentDomain(forName: suite)
    }

    private func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    @Test(.timeLimit(.minutes(1)))
    func anAutomationDueNowStartsWithItsScheduledTime() async throws {
        defer { cleanUp() }
        scheduler.start()
        let automation = addAutomation(.daily(hour: 9, minute: 0))
        #expect(scheduler.plan[automation.id] == (try date("2026-10-02T09:00:00+02:00")))

        clock.now = try date("2026-10-02T09:00:20+02:00")
        scheduler.reschedule()

        let execution = try #require(automations[automation.id]?.lastExecution)
        #expect(execution.scheduledAt == (try date("2026-10-02T09:00:00+02:00")))
        #expect(execution.startedAt == clock.now)
        #expect(scheduler.plan[automation.id] == (try date("2026-10-03T09:00:00+02:00")))
        try await SessionTests.wait { automations[automation.id]?.lastExecution?.outcome != .inCorso }
    }

    @Test func aTimeMissedByMoreThanAMinuteWaitsForTheRecovery() throws {
        defer { cleanUp() }
        scheduler.start()
        let automation = addAutomation(.daily(hour: 9, minute: 0))

        clock.now = try date("2026-10-02T09:05:00+02:00")
        scheduler.reschedule()

        #expect(automations[automation.id]?.executions.isEmpty == true)
        #expect(scheduler.plan[automation.id] == (try date("2026-10-03T09:00:00+02:00")))
    }

    @Test func aChangeCountsFromTheNextTime() throws {
        defer { cleanUp() }
        scheduler.start()
        var automation = addAutomation(.daily(hour: 9, minute: 0))

        automation.recurrence = .hourly(minute: 45)
        automations.update(automation)

        #expect(scheduler.plan[automation.id] == (try date("2026-10-02T08:45:00+02:00")))
    }

    @Test func aPausedAutomationIsNotPlannedUntilResumed() throws {
        defer { cleanUp() }
        scheduler.start()
        let automation = addAutomation(.daily(hour: 9, minute: 0))

        automations.pause(automation.id)
        #expect(scheduler.plan[automation.id] == nil)

        automations.resume(automation.id)
        #expect(scheduler.plan[automation.id] != nil)
    }

    @Test func aNewTimeZoneMovesTheTimeToTheNewLocalOne() throws {
        defer { cleanUp() }
        scheduler.start()
        let automation = addAutomation(.daily(hour: 9, minute: 0))

        clock.calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        scheduler.replan()

        #expect(scheduler.plan[automation.id] == (try date("2026-10-02T09:00:00-04:00")))
    }

    @Test func aMissingProjectPutsTheAutomationInPausaWithWhy() throws {
        defer { cleanUp() }
        let automation = addAutomation(.hourly(minute: 0), in: repos.base.appending(path: "sparito"))

        scheduler.start()

        #expect(automations[automation.id]?.isPaused == true)
        #expect(automations[automation.id]?.pauseReason == .projectMissing)
        #expect(scheduler.plan.isEmpty)
    }

    @Test func anAutomationWithoutARepetitionIsNeverPlanned() throws {
        defer { cleanUp() }
        _ = addAutomation(nil)
        scheduler.start()
        #expect(scheduler.plan.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func differentAutomationsDueTogetherAllStart() async throws {
        defer { cleanUp() }
        scheduler.start()
        let one = addAutomation(.daily(hour: 9, minute: 0), named: "Uno")
        let other = addAutomation(.weekdays(hour: 9, minute: 0), named: "Due")

        clock.now = try date("2026-10-02T09:00:00+02:00")
        scheduler.reschedule()

        #expect(automations[one.id]?.lastExecution?.outcome == .inCorso)
        #expect(automations[other.id]?.lastExecution?.outcome == .inCorso)
        try await SessionTests.wait { store.sessions.allSatisfy { !$0.isRunning } }
        try await SessionTests.wait {
            [one.id, other.id].allSatisfy { automations[$0]?.lastExecution?.outcome != .inCorso }
        }
        #expect(automations[one.id]?.lastExecution?.outcome == .senzaModifiche)
        #expect(automations[other.id]?.lastExecution?.outcome == .senzaModifiche)
    }
}
