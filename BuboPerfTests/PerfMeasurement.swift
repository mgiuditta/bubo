import Foundation

/// One reading for the report of `scripts/perf.sh`, or why a budget was not measured.
///
/// The performance tests attach readings as JSON files named `perf-<id>….json`; the script adds its own.
nonisolated struct PerfMeasurement: Codable, Sendable, Equatable {
    /// The budget read.
    let id: BudgetID
    /// The value in the unit of the budget's row; `nil` when the budget was skipped.
    let value: Double?
    /// Where the value comes from, or why the budget was skipped.
    let note: String

    /// Creates a reading of `value`, in the unit of the budget's row.
    init(_ id: BudgetID, value: Double, from source: String) {
        self.id = id
        self.value = value
        note = source
    }

    /// Creates the record of a budget not measured, for `reason`.
    init(skipping id: BudgetID, because reason: String) {
        self.id = id
        value = nil
        note = reason
    }

    /// The prefix of the attachments that carry a reading.
    static let attachmentPrefix = "perf-"
}
