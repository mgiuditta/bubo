import AppKit
import XCTest

/// Warm launch, memory at rest and the "no `claude` at launch" invariant,
/// against `PerfBudgets`, on the Release build.
///
/// XCTest rather than Swift Testing: only XCTest has UI tests and performance
/// metrics. Values go in the test report; a test fails only beyond
/// `PerfBudgets.failureFactor` times its budget, or on a broken invariant.
nonisolated final class LaunchPerfTests: XCTestCase {
    private static let launchIdentifier =
        "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration"
    private static let memoryIdentifier = "com.apple.dt.XCTMetric_Memory-com.mgiuditta.bubo.physical_absolute"

    override func setUp() {
        RecordedMeasurements.reset()
    }

    @MainActor func testWarmLaunch() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = PerfBudgets.launchIterations
        measure(metrics: [RecordingMetric(XCTApplicationLaunchMetric(waitUntilResponsive: true))], options: options) {
            XCUIApplication().launch()
        }
        XCUIApplication().terminate()

        let seconds = Array(RecordedMeasurements.values(for: Self.launchIdentifier).suffix(PerfBudgets.launchIterations))
        XCTAssertEqual(seconds.count, PerfBudgets.launchIterations)
        let p95 = Measurement(value: try XCTUnwrap(Self.percentile95(of: seconds)), unit: UnitDuration.seconds)
        check(p95.converted(to: .milliseconds), against: PerfBudgets.warmLaunch, named: "Avvio caldo, p95")
    }

    @MainActor func testMemoryAtRest() throws {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [RecordingMetric(XCTMemoryMetric(application: app))], options: options) {
            app.launch()
            // Past the launch work, so the reading is Bubo at rest.
            Thread.sleep(forTimeInterval: 3)
        }
        app.terminate()

        // XCTest's "kB" are 1024 bytes.
        let kibibytes = try XCTUnwrap(RecordedMeasurements.values(for: Self.memoryIdentifier).last)
        let memory = Measurement(value: kibibytes, unit: UnitInformationStorage.kibibytes)
        check(memory.converted(to: .mebibytes), against: PerfBudgets.idleMemory, named: "Memoria a riposo")
    }

    @MainActor func testNoClaudeAfterLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        Thread.sleep(forTimeInterval: PerfBudgets.settleAfterLaunch)

        let bubo = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.mgiuditta.bubo")
                .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        )
        let claudes = try ProcessTree().descendantNames(of: bubo.processIdentifier).filter { $0 == "claude" }
        XCTAssertEqual(claudes.count, PerfBudgets.claudeProcessesAfterLaunch, "Processi claude sotto Bubo dopo l'avvio")
    }

    /// Adds the reading to the report and fails beyond the failure factor.
    @MainActor private func check<U: Dimension>(_ value: Measurement<U>, against budget: Measurement<U>, named name: String) {
        let limit = budget * PerfBudgets.failureFactor
        let style = Measurement<U>.FormatStyle(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        let line = "\(name): \(value.formatted(style)), budget \(budget.formatted(style)), blocca oltre \(limit.formatted(style))"
        let attachment = XCTAttachment(string: line)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print(line)
        XCTAssertLessThanOrEqual(value.converted(to: budget.unit).value, limit.value, line)
    }

    /// The 95th percentile by nearest rank, or `nil` when there are no values.
    private static func percentile95(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let rank = Int((0.95 * Double(values.count)).rounded(.up))
        return values.sorted()[rank - 1]
    }
}
