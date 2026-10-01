import Foundation

/// The budgets of spec 25 that the performance tests and `scripts/perf.sh` check:
/// the only machine-readable copy. The table in `docs/features/25-prestazioni.md`
/// is the one for people; keep the two in step.
nonisolated enum PerfBudgets {
    /// A test fails only beyond this multiple of a budget, since shared runners
    /// are not the reference Mac. Invariants fail at any breach.
    static let failureFactor = 2.0

    /// Warm launch to the interactive HUD, p95.
    static let warmLaunch = Measurement(value: 500, unit: UnitDuration.milliseconds)

    /// Launches measured for the warm launch.
    static let launchIterations = 10

    /// Cold launch to the interactive HUD, after a restart of the Mac.
    static let coldLaunch = Measurement(value: 1, unit: UnitDuration.seconds)

    /// From opening a Sessione to its `claude` ready.
    static let sessionReady = Measurement(value: 1, unit: UnitDuration.seconds)

    /// From the message to a suspended Sessione to its sending to `claude`.
    static let sessionResume = Measurement(value: 1, unit: UnitDuration.seconds)

    /// Bubo at rest: HUD and Orb, no Sessions, Index not loaded.
    static let idleMemory = Measurement(value: 100, unit: UnitInformationStorage.mebibytes)

    /// Bubo with 10 Sessions open and idle, agent processes excluded.
    static let memoryWithTenSessions = Measurement(value: 150, unit: UnitInformationStorage.mebibytes)

    /// Bubo's CPU with 10 Sessions open and idle, in percent of one core.
    static let cpuWithTenSessions = 1.0

    /// The agent bridge.
    static let bridgeMemory = Measurement(value: 50, unit: UnitInformationStorage.mebibytes)

    /// Bubo, bridge and every `claude` with 10 Sessions and an empty configuration, deduplicated.
    static let totalMemoryWithTenSessions = Measurement(value: 1.6, unit: UnitInformationStorage.gibibytes)

    /// Bubo and bridge with 10 suspended Sessions, no `claude`.
    static let memoryWithTenSuspendedSessions = Measurement(value: 200, unit: UnitInformationStorage.mebibytes)

    /// The Sessions the budgets "with 10 Sessions" ask for.
    static let sessionsForMemory = 10

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

    /// Galassia frames drawn while it is still, covered or minimized: an invariant.
    static let galaxyFramesWhileStill = 0

    /// Hitch time per second of the HUD's Notte animations: 10 ms per second is a ratio of 1%.
    static let hitchTimeRatio = Measurement(value: 10, unit: UnitDuration.milliseconds)

    /// How long the hitches of the HUD's animations are measured.
    static let hitchSampleDuration: TimeInterval = 5

    /// The longest a main-thread interval of a main flow may take: beyond it is a hang.
    static let mainThreadInterval = Measurement(value: 100, unit: UnitDuration.milliseconds)

    /// One row per budget of spec 25 whose CI column is 2×, invariante or perf.sh, in the table's order:
    /// what the report of `scripts/perf.sh` covers.
    static let reported: [ReportedBudget] = [
        ReportedBudget(.warmLaunch, area: "Avvio caldo, p95", limit: warmLaunch, gate: .doubled),
        ReportedBudget(.coldLaunch, area: "Avvio freddo", limit: coldLaunch.converted(to: .milliseconds),
                       gate: .referenceMac),
        ReportedBudget(.claudeAfterLaunch, area: "Processi claude all'avvio",
                       count: claudeProcessesAfterLaunch),
        ReportedBudget(.sessionReady, area: "Sessione pronta", limit: sessionReady.converted(to: .milliseconds),
                       gate: .referenceMac),
        ReportedBudget(.sessionResume, area: "Ripresa dopo sospensione",
                       limit: sessionResume.converted(to: .milliseconds), gate: .referenceMac),
        ReportedBudget(.idleMemory, area: "Bubo a riposo", limit: idleMemory, gate: .doubled),
        ReportedBudget(.memoryWithTenSessions, area: "Bubo con 10 Sessioni", limit: memoryWithTenSessions,
                       gate: .referenceMac),
        ReportedBudget(.cpuWithTenSessions, area: "CPU di Bubo con 10 Sessioni", limit: cpuWithTenSessions,
                       unit: "%", gate: .referenceMac),
        ReportedBudget(.bridgeMemory, area: "Ponte", limit: bridgeMemory, gate: .referenceMac),
        ReportedBudget(.totalMemoryWithTenSessions, area: "Totale con 10 Sessioni",
                       limit: totalMemoryWithTenSessions.converted(to: .mebibytes), gate: .referenceMac),
        ReportedBudget(.memoryWithTenSuspendedSessions, area: "10 Sessioni sospese",
                       limit: memoryWithTenSuspendedSessions, gate: .referenceMac),
        ReportedBudget(.orbGPUTime, area: "Orb, tempo GPU p95", limit: orbGPUTime, gate: .doubled),
        ReportedBudget(.framesWhileCovered, area: "Orb coperto, fotogrammi", count: framesWhileCovered),
        ReportedBudget(.galaxyFramesWhileStill, area: "Galassia ferma, fotogrammi", count: galaxyFramesWhileStill),
        ReportedBudget(.mainThreadInterval, area: "Intervallo più lungo sul main thread",
                       limit: mainThreadInterval, gate: .doubled),
        ReportedBudget(.hitchTimeRatio, area: "Hitch dell'HUD, ms al secondo", limit: hitchTimeRatio,
                       gate: .doubled),
    ]
}

/// The identifier of a budget in the report, shared by the tests and `scripts/perf.sh`.
nonisolated enum BudgetID: String, Codable, CaseIterable, Sendable {
    case warmLaunch = "avvio-caldo"
    case coldLaunch = "avvio-freddo"
    case claudeAfterLaunch = "claude-all-avvio"
    case sessionReady = "sessione-pronta"
    case sessionResume = "ripresa-sessione"
    case idleMemory = "memoria-a-riposo"
    case memoryWithTenSessions = "memoria-10-sessioni"
    case cpuWithTenSessions = "cpu-10-sessioni"
    case bridgeMemory = "memoria-ponte"
    case totalMemoryWithTenSessions = "totale-10-sessioni"
    case memoryWithTenSuspendedSessions = "memoria-10-sessioni-sospese"
    case orbGPUTime = "orb-tempo-gpu"
    case framesWhileCovered = "orb-coperto"
    case galaxyFramesWhileStill = "galassia-ferma"
    case mainThreadInterval = "intervallo-main-thread"
    case hitchTimeRatio = "hitch-hud"
}

/// A budget as the report shows it: a limit in one unit, and how the budget gates a change.
nonisolated struct ReportedBudget: Codable, Sendable, Equatable {
    /// How a budget gates a change: the CI column of spec 25's table.
    enum Gate: String, Codable, Sendable {
        /// Blocks a pull request beyond twice the budget; exact on the reference Mac.
        case doubled = "2×"
        /// Blocks at any breach: the value must equal the limit.
        case invariant = "invariante"
        /// Checked only on the reference Mac, by `scripts/perf.sh`.
        case referenceMac = "perf.sh"
    }

    /// The budget's identifier.
    let id: BudgetID
    /// What is measured, as the report names it.
    let area: String
    /// The highest value within the budget, or the value an invariant requires.
    let limit: Double
    /// The symbol of the unit of `limit` and of the measurements, such as `ms` or `MiB`; empty for a count.
    let unit: String
    /// How the budget gates a change.
    let gate: Gate

    /// Creates the row of a budget measured in `limit`'s unit.
    init<UnitType: Dimension>(_ id: BudgetID, area: String, limit: Measurement<UnitType>, gate: Gate) {
        self.init(id, area: area, limit: limit.value, unit: limit.unit.symbol, gate: gate)
    }

    /// Creates the row of an invariant: a count that must be exactly `count`.
    init(_ id: BudgetID, area: String, count: Int) {
        self.init(id, area: area, limit: Double(count), unit: "", gate: .invariant)
    }

    /// Creates the row of a budget whose unit is not a `Dimension`, such as a percentage.
    init(_ id: BudgetID, area: String, limit: Double, unit: String, gate: Gate) {
        self.id = id
        self.area = area
        self.limit = limit
        self.unit = unit
        self.gate = gate
    }

    /// Whether `value`, in the row's unit, keeps the budget: equal to the limit for an invariant, at most it otherwise.
    func isKept(by value: Double) -> Bool {
        gate == .invariant ? value == limit : value <= limit
    }

    /// Whether `value` would block a pull request in CI: beyond twice the limit of a 2× budget, any breach of an invariant.
    func blocksPullRequest(_ value: Double) -> Bool {
        switch gate {
        case .doubled: value > limit * PerfBudgets.failureFactor
        case .invariant: !isKept(by: value)
        case .referenceMac: false
        }
    }
}
