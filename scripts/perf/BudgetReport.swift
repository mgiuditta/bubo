import Foundation

/// The report of `scripts/perf.sh`: one row per budget, with the value read, the limit and the outcome.
nonisolated struct BudgetReport: Codable, Sendable {
    /// What a reading means for its budget.
    enum Outcome: String, Codable, Sendable {
        /// Within the budget, or the invariant holds.
        case kept = "ok"
        /// Beyond the budget.
        case exceeded = "oltre il budget"
        /// The invariant does not hold.
        case broken = "invariante rotto"
        /// No reading.
        case notMeasured = "non misurato"
    }

    /// One budget with its reading.
    struct Row: Codable, Sendable, Equatable {
        /// The budget.
        let budget: ReportedBudget
        /// The worst reading, in the unit of the budget; `nil` when not measured.
        let value: Double?
        /// What the reading means.
        let outcome: Outcome
        /// Whether the reading would also block a pull request in CI.
        let blocksPullRequest: Bool
        /// Where the readings come from, or why the budget was not measured.
        let notes: [String]
    }

    /// When the measurements were taken.
    let date: Date
    /// One row per budget, in the order of the budgets.
    let rows: [Row]

    /// Creates the report of `measurements` against `budgets`.
    ///
    /// When a budget has more than one reading, the highest counts: a budget holds only if every reading keeps it.
    init(budgets: [ReportedBudget] = PerfBudgets.reported, measurements: [PerfMeasurement], date: Date = .now) {
        self.date = date
        rows = budgets.map { budget in
            let readings = measurements.filter { $0.id == budget.id }
            let values = readings.compactMap(\.value)
            let notes = Array(Set(readings.map(\.note))).sorted()
            guard let worst = values.max() else {
                return Row(budget: budget, value: nil, outcome: .notMeasured, blocksPullRequest: false,
                           notes: notes.isEmpty ? [Self.missingReading] : notes)
            }
            let outcome: Outcome = budget.isKept(by: worst) ? .kept : (budget.gate == .invariant ? .broken : .exceeded)
            return Row(budget: budget, value: worst, outcome: outcome,
                       blocksPullRequest: budget.blocksPullRequest(worst), notes: notes)
        }
    }

    /// Whether every budget measured is kept; budgets not measured do not count.
    var isWithinBudgets: Bool {
        rows.allSatisfy { $0.outcome == .kept || $0.outcome == .notMeasured }
    }

    /// The report as a Markdown page, for people.
    var markdown: String {
        let header = """
            # Prestazioni di Bubo — \(date.formatted(.iso8601))

            Budget della spec 25 sul Mac di riferimento. \(summary)

            | Area | Valore | Budget | CI | Esito | Note |
            |---|---|---|---|---|---|

            """
        return header + rows.map { row in
            let budget = row.budget
            let comparison = budget.gate == .invariant ? "=" : "≤"
            let value = row.value.map { Self.format($0, unit: budget.unit) } ?? "—"
            let outcome = row.blocksPullRequest ? "\(row.outcome.rawValue), blocca la CI" : row.outcome.rawValue
            let notes = row.notes.joined(separator: "; ").replacing("|", with: "\\|")
            return "| \(budget.area) | \(value) | \(comparison) \(Self.format(budget.limit, unit: budget.unit)) "
                + "| \(budget.gate.rawValue) | \(outcome) | \(notes) |"
        }.joined(separator: "\n") + "\n"
    }

    /// The report as JSON, for machines.
    ///
    /// - Throws: An error if a row cannot be encoded.
    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private var summary: String {
        let count = { (outcome: Outcome) in rows.count { $0.outcome == outcome } }
        return "Rispettati \(count(.kept)), superati \(count(.exceeded) + count(.broken)), non misurati \(count(.notMeasured))."
    }

    private static let missingReading = "Nessuna lettura: test saltato o fallito, vedi BuboPerf.xcresult"

    private static func format(_ value: Double, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
