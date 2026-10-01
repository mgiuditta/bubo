import AppKit
import XCTest

/// The Orb's GPU time, the covered Panel's frames, the HUD's hitches and the main-thread intervals,
/// against `PerfBudgets`, on the Release build.
///
/// The Orb's frames come from the log Bubo writes with `-orbFrameLog`. Without Metal the frame tests
/// are skipped, not failed.
nonisolated final class FramePerfTests: XCTestCase {
    override func setUp() {
        RecordedMeasurements.reset()
    }

    @MainActor func testOrbGPUTime() throws {
        try skipWithoutMetal(reportedAs: .orbGPUTime, because: "Nessun Metal: tempo GPU dell'Orb non misurato.")
        // `scripts/perf.sh` reads the Orb's frames from the Metal HUD's log too, so it asks for that log.
        let logsMetalHUD = ProcessInfo.processInfo.environment["BUBO_METAL_HUD"] == "1"
        let (app, log) = launchShowingPanel(environment: logsMetalHUD ? Self.metalHUDLogging : [:])
        defer { app.terminate() }
        // The Orb morphs at 60 fps from the launch: wait for the frames, and a margin.
        Thread.sleep(forTimeInterval: Double(PerfBudgets.orbFrames) / 60 + 2)

        let gpuTimes = try FrameLog(contentsOf: log).gpuTimes.suffix(PerfBudgets.orbFrames)
        XCTAssertEqual(gpuTimes.count, PerfBudgets.orbFrames, "Fotogrammi dell'Orb nel log")
        let p95 = Measurement(value: try XCTUnwrap(gpuTimes.percentile95()), unit: UnitDuration.seconds)
        check(p95.converted(to: .milliseconds), against: PerfBudgets.orbGPUTime, named: "Tempo GPU dell'Orb, p95",
              reportedAs: .orbGPUTime)
    }

    @MainActor func testCoveredPanelDrawsNoFrames() throws {
        try skipWithoutMetal(reportedAs: .framesWhileCovered, because: "Nessun Metal: fotogrammi del Panel non contati.")
        let (app, log) = launchShowingPanel()
        defer { app.terminate() }
        RunLoop.current.run(until: .now + 1)
        XCTAssertGreaterThan(try FrameLog(contentsOf: log).frameCount, 0, "L'Orb del Panel non ha disegnato.")

        // Opaque windows above the floating Panel, on every screen.
        let covers = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.orderFrontRegardless()
            return window
        }
        defer { covers.forEach { $0.close() } }
        // Time for the occlusion change, and for the frames already on the GPU to be logged.
        RunLoop.current.run(until: .now + 1)
        let before = try FrameLog(contentsOf: log).frameCount
        RunLoop.current.run(until: .now + PerfBudgets.coveredDuration)
        let drawn = try FrameLog(contentsOf: log).frameCount - before
        record(Double(drawn), reportedAs: .framesWhileCovered, from: "Fotogrammi dell'Orb a Panel coperto per 10 s")

        XCTAssertEqual(drawn, PerfBudgets.framesWhileCovered, "Fotogrammi dell'Orb a Panel coperto per 10 s")
    }

    @MainActor func testHUDAnimationHitches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-showsPanel", "NO"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        // The rings of the HUD turn on their own: the Notte animation measured.
        measure(metrics: [RecordingMetric(XCTHitchMetric(application: app))], options: options) {
            Thread.sleep(forTimeInterval: PerfBudgets.hitchSampleDuration)
        }

        let ratio = try XCTUnwrap(RecordedMeasurements.measurements {
            $0.hasPrefix("com.apple.dt.XCTMetric_Hitch") && $0.hasSuffix(".time.ratio") && !$0.contains("normalized")
        }.last)
        check(Measurement(value: ratio.value, unit: UnitDuration.milliseconds), against: PerfBudgets.hitchTimeRatio,
              named: "Rapporto di hitch dell'HUD, ms al secondo (XCTest: \(ratio.unitSymbol))", reportedAs: .hitchTimeRatio)
    }

    /// Opens a real Sessione on the last Progetto, so it runs only with `TEST_RUNNER_BUBO_LIVE=1`.
    ///
    /// The Progetto must be trusted, or the trust dialog comes before the Sessione opens.
    @MainActor func testOpeningASessionHasNoHang() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUBO_LIVE"] == "1", "Solo con BUBO_LIVE=1")
        let app = XCUIApplication()
        app.launchArguments = ["-showsPanel", "NO"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        let opening = XCTOSSignpostMetric(subsystem: "com.mgiuditta.bubo", category: "PointsOfInterest",
                                          name: "Apertura Sessione")
        measure(metrics: [RecordingMetric(opening)], options: options) {
            app.typeKey("n", modifierFlags: .command)
            let create = app.buttons["Crea"]
            XCTAssertTrue(create.waitForExistence(timeout: 10), "Il foglio della nuova Sessione non si è aperto.")
            // The prompt has the focus as the sheet opens.
            app.typeText("Rispondi solo con la parola: pronto")
            create.click()
            XCTAssertTrue(create.waitForNonExistence(timeout: 10), "La Sessione non si è aperta.")
        }

        let durations = RecordedMeasurements.measurements {
            $0.hasPrefix("com.apple.dt.XCTMetric_OSSignpost") && $0.hasSuffix(".duration")
        }
        XCTAssertFalse(durations.isEmpty, "Nessun intervallo Apertura Sessione.")
        for duration in durations {
            let seconds = Measurement(value: duration.value, unit: UnitDuration.seconds)
            check(seconds.converted(to: .milliseconds), against: PerfBudgets.mainThreadInterval,
                  named: "Apertura Sessione sul main thread", reportedAs: .mainThreadInterval)
        }
    }

    /// The identifier of the HUD window, as SwiftUI names it after the scene id.
    private static let hudWindow = "hud"

    /// The environment that has Metal write a `metal-HUD:` line per second to the system log.
    private static let metalHUDLogging = ["MTL_HUD_ENABLED": "1", "MTL_HUD_LOG_ENABLED": "1"]

    /// Launches Bubo writing its Orb frames to a new log, and closes the HUD so the Panel shows.
    ///
    /// - Parameter environment: Variables added to Bubo's environment.
    @MainActor private func launchShowingPanel(environment: [String: String] = [:]) -> (app: XCUIApplication, log: URL) {
        let log = URL.temporaryDirectory.appending(path: "orb-frames-\(UUID().uuidString).log")
        let app = XCUIApplication()
        app.launchArguments = ["-showsPanel", "YES", "-orbFrameLog", log.path]
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.dialogs.buttons["Bubo"].waitForExistence(timeout: 10), "Il Panel non è comparso.")
        return (app, log)
    }
}
