import Metal
import XCTest

extension XCTestCase {
    /// Adds the reading to the report and fails beyond `PerfBudgets.failureFactor` times `budget`.
    ///
    /// The reading is also attached as JSON, for the report of `scripts/perf.sh`, under `id`.
    @MainActor func check<U: Dimension>(_ value: Measurement<U>, against budget: Measurement<U>, named name: String,
                                        reportedAs id: BudgetID) {
        let limit = budget * PerfBudgets.failureFactor
        let style = Measurement<U>.FormatStyle(width: .abbreviated, usage: .asProvided,
                                               numberFormatStyle: .number.precision(.fractionLength(0...2)))
        let line = "\(name): \(value.formatted(style)), budget \(budget.formatted(style)), blocca oltre \(limit.formatted(style))"
        let attachment = XCTAttachment(string: line)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print(line)
        record(value.converted(to: budget.unit).value, reportedAs: id, from: name)
        XCTAssertLessThanOrEqual(value.converted(to: budget.unit).value, limit.value, line)
    }

    /// Attaches `value`, in the unit of the budget's row, as a reading for the report of `scripts/perf.sh`.
    @MainActor func record(_ value: Double, reportedAs id: BudgetID, from source: String) {
        attach(PerfMeasurement(id, value: value, from: source))
    }

    /// Skips the test on a Mac without a usable Metal device, leaving `id` in the report as not measured.
    ///
    /// The paravirtual GPU of a virtual machine, such as GitHub's macOS runners, counts as none:
    /// there the Orb's transparent Panel blacks out the screen instead of drawing.
    ///
    /// - Throws: `XCTSkip` with `reason` when there is no usable Metal device.
    @MainActor func skipWithoutMetal(reportedAs id: BudgetID, because reason: String) throws {
        if let device = MTLCreateSystemDefaultDevice(), !device.name.localizedStandardContains("Paravirtual") { return }
        attach(PerfMeasurement(skipping: id, because: reason))
        throw XCTSkip(reason)
    }

    @MainActor private func attach(_ measurement: PerfMeasurement) {
        let id = measurement.id
        do {
            let attachment = XCTAttachment(data: try JSONEncoder().encode(measurement), uniformTypeIdentifier: "public.json")
            attachment.name = "\(PerfMeasurement.attachmentPrefix)\(id.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Lettura di \(id.rawValue) non allegata: \(error)")
        }
    }
}
