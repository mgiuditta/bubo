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
    /// Iterations of the warm launch that may come without a launch metric.
    private static let missingLaunchMetricsAllowed = 2
    private static let memoryIdentifier = "com.apple.dt.XCTMetric_Memory-com.mgiuditta.bubo.physical_absolute"

    override func setUp() {
        RecordedMeasurements.reset()
    }

    @MainActor func testWarmLaunch() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = PerfBudgets.launchIterations
        // On a GitHub VM an iteration now and then delivers no launch metric, and XCTest fails the test
        // for it: the iterations that have one still make the p95, as long as few are missing.
        let missingMetric = XCTExpectedFailure.Options()
        missingMetric.isStrict = false
        missingMetric.issueMatcher = { $0.compactDescription.contains("unexpected number of metrics") }
        XCTExpectFailure("Iterazione senza metrica di avvio", options: missingMetric) {
            // A new instance at each iteration, as XCTest's own example does.
            measure(metrics: [RecordingMetric(XCTApplicationLaunchMetric(waitUntilResponsive: true))], options: options) {
                XCUIApplication.bubo().launch()
            }
        }
        XCUIApplication.bubo().terminate()

        let seconds = Array(RecordedMeasurements.values(for: Self.launchIdentifier).suffix(PerfBudgets.launchIterations))
        XCTAssertGreaterThanOrEqual(seconds.count, PerfBudgets.launchIterations - Self.missingLaunchMetricsAllowed,
                                    "Troppe iterazioni senza metrica di avvio")
        let p95 = Measurement(value: try XCTUnwrap(seconds.percentile95()), unit: UnitDuration.seconds)
        check(p95.converted(to: .milliseconds), against: PerfBudgets.warmLaunch, named: "Avvio caldo, p95",
              reportedAs: .warmLaunch)
    }

    @MainActor func testMemoryAtRest() throws {
        let app = XCUIApplication.bubo()
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
        check(memory.converted(to: .mebibytes), against: PerfBudgets.idleMemory, named: "Memoria a riposo",
              reportedAs: .idleMemory)
    }

    @MainActor func testNoClaudeAfterLaunch() throws {
        let app = XCUIApplication.bubo()
        app.launch()
        defer { app.terminate() }
        Thread.sleep(forTimeInterval: PerfBudgets.settleAfterLaunch)

        let bubo = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.mgiuditta.bubo")
                .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        )
        let claudes = try ProcessTree().descendantNames(of: bubo.processIdentifier).filter { $0 == "claude" }
        record(Double(claudes.count), reportedAs: .claudeAfterLaunch, from: "Processi claude sotto Bubo dopo l'avvio")
        XCTAssertEqual(claudes.count, PerfBudgets.claudeProcessesAfterLaunch, "Processi claude sotto Bubo dopo l'avvio")
    }
}
