import AppKit
import os

/// Starts the Esecuzioni of the Automazioni at the times of their Ripetizioni, with one timer for the soonest of them
/// (spec 19).
///
/// The times are planned again at each change of an Automazione, at the Mac's waking, and when its clock or its time
/// zone change: "ogni giorno alle 9" stays at 9 of the new local time. Automazioni due together all start, with no
/// queue. No `NSBackgroundActivityScheduler`: its times are not precise.
final class AutomationScheduler {
    /// How late after its time an Esecuzione still starts; a time missed by more waits for the recovery.
    static let lateness: TimeInterval = 60
    /// How far back the recovery looks for missed times.
    static let recoveryWindow: TimeInterval = 7 * 24 * 60 * 60
    /// The key, in the user defaults, of the last moment the scheduler was watching: until then no time was missed.
    static let watchedUntilKey = "automations.watchedUntil"

    /// When each active Automazione runs next, by id.
    private(set) var plan: [Automation.ID: Date] = [:]
    /// Called when the recovery starts an Esecuzione, with its Automazione and the missed time it recovers.
    var onRecovery: (_ automation: Automation, _ scheduledAt: Date) -> Void = { _, _ in }
    /// "Tieni sveglio il Mac", taken while an Automazione is due within two hours and the switch is on.
    let keepAwake = KeepAwake()

    private let automations: AutomationStore
    private let runner: ExecutionRunner
    private let calendar: () -> Calendar
    private let now: () -> Date
    private let defaults: UserDefaults
    private var timer: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    /// Whether the plan is being made: the changes it makes to the Automazioni do not start it again.
    private var isPlanning = false
    /// Whether the Mac is going to sleep or asleep: no timer, nothing starts, until it wakes.
    private var isAsleep = false

    /// Creates a scheduler for `automations`, starting their Esecuzioni with `runner`, at the times of `calendar`;
    /// `defaults` keeps when it last watched, and the switch of "Tieni sveglio il Mac".
    init(automations: AutomationStore, runner: ExecutionRunner,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent }, now: @escaping () -> Date = { .now },
         defaults: UserDefaults = .standard) {
        self.automations = automations
        self.runner = runner
        self.calendar = calendar
        self.now = now
        self.defaults = defaults
    }

    isolated deinit {
        timer?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Plans the Esecuzioni and follows the changes to the Automazioni, to the clock, to the time zone and to the Mac's
    /// sleep. An Esecuzione left in corso by Bubo's quitting becomes Interrotta; the times missed while Bubo was
    /// closed are recovered.
    func start() {
        runner.markInterrupted()
        recover()
        automations.onChange = { [weak self] in self?.reschedule() }
        let replan: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleep() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            },
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main,
                                                   using: replan),
            NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main,
                                                   using: replan),
            // The switch of "Tieni sveglio il Mac".
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateKeepAwake() }
            },
        ]
        reschedule()
    }

    /// The Mac is going to sleep: no timer, the Esecuzioni at work become Interrotte, every assertion goes, and the
    /// time is kept for the recovery at waking.
    func sleep() {
        isAsleep = true
        timer?.cancel()
        timer = nil
        defaults.set(now(), forKey: Self.watchedUntilKey)
        runner.interruptAll()
        keepAwake.release()
        Logger.automations.notice("Mac going to sleep")
    }

    /// The Mac woke: the times missed while it slept are recovered, then every time is planned again.
    func wake() {
        isAsleep = false
        Logger.automations.notice("Mac woke")
        recover()
        replan()
    }

    /// Recovers the times missed since the scheduler last watched, at most ``recoveryWindow`` ago: for each active
    /// Automazione, each missed time but the latest becomes a Saltata in its history, and one Esecuzione starts for
    /// the latest, announced by ``onRecovery``. Nothing the first time, with nothing watched before.
    func recover() {
        guard let watched = defaults.object(forKey: Self.watchedUntilKey) as? Date else { return }
        isPlanning = true
        defer { isPlanning = false }
        let date = now()
        let calendar = calendar()
        let since = max(watched, date.addingTimeInterval(-Self.recoveryWindow))
        for automation in automations.automations where !automation.isPaused {
            guard let recurrence = automation.recurrence,
                  FileManager.default.fileExists(atPath: automation.project.path)
            else { continue }
            let recorded = Set(automation.executions.compactMap(\.scheduledAt))
            let missed = recurrence.dates(after: since, through: date, in: calendar).filter { !recorded.contains($0) }
            guard let latest = missed.last else { continue }
            for time in missed.dropLast() {
                automations.record(Execution(startedAt: time, scheduledAt: time, outcome: .saltata,
                                             skipReason: .assente), for: automation.id)
            }
            Logger.automations.notice("Recovery: \(missed.count) missed times")
            if runner.run(automation.id, scheduledAt: latest, at: date) != nil {
                onRecovery(automation, latest)
            }
        }
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
        guard !isPlanning, !isAsleep else { return }
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
        defaults.set(date, forKey: Self.watchedUntilKey)
        updateKeepAwake()
    }

    /// Holds "Tieni sveglio il Mac" while its switch is on and an Automazione is due within two hours.
    private func updateKeepAwake() {
        guard !isAsleep else { return }
        let date = now()
        let isDueSoon = plan.values.contains { $0.timeIntervalSince(date) <= KeepAwake.window }
        keepAwake.hold(defaults.bool(forKey: KeepAwake.defaultsKey) && isDueSoon)
    }

    private func setTimer(from date: Date) {
        timer?.cancel()
        guard let soonest = plan.values.min() else {
            timer = nil
            return
        }
        // Also two hours before, when "Tieni sveglio il Mac" takes its assertion.
        let awake = soonest.addingTimeInterval(-KeepAwake.window)
        let delay = max(0, (awake > date ? awake : soonest).timeIntervalSince(date))
        timer = Task { [weak self] in
            // The continuous clock counts the sleep too: on waking the timer is due, and the plan is made again.
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reschedule()
        }
    }
}
