import AppKit
import os

/// Starts the Esecuzioni of the Automazioni at the times of their Ripetizioni, with one timer for the soonest of them
/// (spec 19).
///
/// The times are planned again at each change of an Automazione, at the Mac's waking, and when its clock or its time
/// zone change: "ogni giorno alle 9" stays at 9 of the new local time. Automazioni due together all start, with no
/// queue. No `NSBackgroundActivityScheduler`: its times are not precise.
final class AutomationScheduler {
    /// How late after its time an Esecuzione still starts; a time missed by more waits for the recovery (#170).
    static let lateness: TimeInterval = 60

    /// When each active Automazione runs next, by id.
    private(set) var plan: [Automation.ID: Date] = [:]

    private let automations: AutomationStore
    private let runner: ExecutionRunner
    private let calendar: () -> Calendar
    private let now: () -> Date
    private var timer: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    /// Whether the plan is being made: the changes it makes to the Automazioni do not start it again.
    private var isPlanning = false

    /// Creates a scheduler for `automations`, starting their Esecuzioni with `runner`, at the times of `calendar`.
    init(automations: AutomationStore, runner: ExecutionRunner,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent }, now: @escaping () -> Date = { .now }) {
        self.automations = automations
        self.runner = runner
        self.calendar = calendar
        self.now = now
    }

    isolated deinit {
        timer?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Plans the Esecuzioni and follows the changes to the Automazioni, to the clock and to the time zone. An
    /// Esecuzione left in corso by Bubo's quitting becomes Interrotta.
    func start() {
        runner.markInterrupted()
        automations.onChange = { [weak self] in self?.reschedule() }
        let replan: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                              queue: .main, using: replan),
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main,
                                                   using: replan),
            NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main,
                                                   using: replan),
        ]
        reschedule()
    }

    /// Plans every time again from now, forgetting the ones planned before: after a sleep, or a change of the clock or
    /// of the time zone.
    func replan() {
        plan = [:]
        reschedule()
    }

    /// Starts the Esecuzioni due now, plans the next times and sets the timer for the soonest.
    ///
    /// An Automazione whose Progetto's folder is gone goes in pausa, with why.
    func reschedule() {
        guard !isPlanning else { return }
        isPlanning = true
        defer { isPlanning = false }
        let date = now()
        let calendar = calendar()
        var due: [(Automation.ID, Date)] = []
        var missing: [Automation.ID] = []
        var next: [Automation.ID: Date] = [:]
        for automation in automations.automations where !automation.isPaused {
            let planned = plan[automation.id].flatMap { planned in
                planned <= date && date.timeIntervalSince(planned) <= Self.lateness ? planned : nil
            }
            let soonest = automation.nextDate(after: date, in: calendar)
            guard planned != nil || soonest != nil else { continue }
            guard FileManager.default.fileExists(atPath: automation.project.path) else {
                missing.append(automation.id)
                continue
            }
            if let planned { due.append((automation.id, planned)) }
            if let soonest { next[automation.id] = soonest }
        }
        plan = next
        for id in missing {
            automations.pause(id, reason: .projectMissing)
            Logger.automations.notice("Automazione paused: Progetto missing")
        }
        for (id, scheduledAt) in due {
            runner.run(id, scheduledAt: scheduledAt, at: date)
        }
        setTimer(from: date)
    }

    private func setTimer(from date: Date) {
        timer?.cancel()
        guard let soonest = plan.values.min() else {
            timer = nil
            return
        }
        let delay = max(0, soonest.timeIntervalSince(date))
        timer = Task { [weak self] in
            // The continuous clock counts the sleep too: on waking the timer is due, and the plan is made again.
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reschedule()
        }
    }
}
