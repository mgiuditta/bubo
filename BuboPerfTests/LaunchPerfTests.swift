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
        let p95 = Measurement(value: try XCTUnwrap(seconds.percentile95()), unit: UnitDuration.seconds)
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
}
