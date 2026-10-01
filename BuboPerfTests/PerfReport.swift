import XCTest

extension XCTestCase {
    /// Adds the reading to the report and fails beyond `PerfBudgets.failureFactor` times `budget`.
    @MainActor func check<U: Dimension>(_ value: Measurement<U>, against budget: Measurement<U>, named name: String) {
        let limit = budget * PerfBudgets.failureFactor
        let style = Measurement<U>.FormatStyle(width: .abbreviated, usage: .asProvided,
                                               numberFormatStyle: .number.precision(.fractionLength(0...2)))
        let line = "\(name): \(value.formatted(style)), budget \(budget.formatted(style)), blocca oltre \(limit.formatted(style))"
        let attachment = XCTAttachment(string: line)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print(line)
        XCTAssertLessThanOrEqual(value.converted(to: budget.unit).value, limit.value, line)
    }
}
