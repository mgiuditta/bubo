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
    static let launchIterations = 10

    /// Bubo at rest: HUD and Orb, no Sessions, Index not loaded.
    static let idleMemory = Measurement(value: 100, unit: UnitInformationStorage.mebibytes)

    /// `claude` processes under Bubo after launch: an invariant.
    static let claudeProcessesAfterLaunch = 0

    /// How long after launch the `claude` invariant is checked.
    static let settleAfterLaunch: TimeInterval = 10

    /// The Orb's GPU time per frame, p95, over `orbFrames` Morph frames.
    static let orbGPUTime = Measurement(value: 4, unit: UnitDuration.milliseconds)

    /// Orb frames measured for the GPU time: 10 s at 60 fps.
    static let orbFrames = 600

    /// Orb frames drawn while the Panel is covered: an invariant.
    static let framesWhileCovered = 0

    /// How long the Panel stays covered.
    static let coveredDuration: TimeInterval = 10

    /// Hitch time per second of the HUD's Notte animations: 10 ms per second is a ratio of 1%.
    static let hitchTimeRatio = Measurement(value: 10, unit: UnitDuration.milliseconds)

    /// How long the hitches of the HUD's animations are measured.
    static let hitchSampleDuration: TimeInterval = 5

    /// The longest a main-thread interval of a main flow may take: beyond it is a hang.
    static let mainThreadInterval = Measurement(value: 100, unit: UnitDuration.milliseconds)
}
