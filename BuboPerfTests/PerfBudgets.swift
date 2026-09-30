import Foundation

/// The budgets of spec 25 that the performance tests check: the only
/// machine-readable copy. The table in `docs/features/25-prestazioni.md` is the
/// one for people; keep the two in step.
enum PerfBudgets {
    /// A test fails only beyond this multiple of a budget, since shared runners
    /// are not the reference Mac. Invariants fail at any breach.
    static let failureFactor = 2.0

    /// Warm launch to the interactive HUD, p95.
    static let warmLaunch = Measurement(value: 500, unit: UnitDuration.milliseconds)

    /// Launches measured for the warm launch.
    static let launchIterations = 5

    /// Bubo at rest: HUD and Orb, no Sessions, Index not loaded.
    static let idleMemory = Measurement(value: 100, unit: UnitInformationStorage.megabytes)

    /// `claude` processes under Bubo after launch: an invariant.
    static let claudeProcessesAfterLaunch = 0

    /// How long after launch the `claude` invariant is checked.
    static let settleAfterLaunch: TimeInterval = 10
}
