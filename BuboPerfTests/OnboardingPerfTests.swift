import Foundation
import XCTest

/// The machine's part of the 60-second onboarding (spec 26): from launch to the first token, with automatic clicks,
/// and no `claude` at launch once the onboarding is over.
///
/// Each onboarding runs in a `FakeClaudeHome`, so it is a first launch whatever the Mac holds. The `claude` is a fake
/// one that answers at once; with `TEST_RUNNER_BUBO_LIVE=1` it is the user's, and the first token comes from Anthropic.
nonisolated final class OnboardingPerfTests: XCTestCase {
    /// The domain of Bubo's preferences, which stay the user's whatever the home.
    private static let bubo = "com.mgiuditta.bubo"
    /// The onboarding's keys in Bubo's preferences, as `OnboardingFlow` names them.
    private static let onboardingKeys = ["onboardingCompleted", "onboardingPendingQuestion"]
    /// The question the onboarding sends: the first suggestion, chosen with a click.
    private static let suggestion = "Spiegami com'è fatto questo Progetto"

    private var homes: [FakeClaudeHome] = []
    /// The onboarding's keys as they were before the test, put back after it.
    private var savedPreferences: [String: CFPropertyList] = [:]

    override func setUp() {
        RecordedMeasurements.reset()
        for key in Self.onboardingKeys {
            savedPreferences[key] = CFPreferencesCopyAppValue(key as CFString, Self.bubo as CFString)
        }
    }

    override func tearDown() {
        // A test stopped halfway leaves a question waiting: the user's Bubo would show the onboarding again.
        for key in Self.onboardingKeys {
            CFPreferencesSetAppValue(key as CFString, savedPreferences[key], Self.bubo as CFString)
        }
        CFPreferencesAppSynchronize(Self.bubo as CFString)
        homes.forEach { $0.remove() }
    }

    @MainActor func testLaunchToFirstToken() throws {
        let isLive = ProcessInfo.processInfo.environment["BUBO_LIVE"] == "1"
        var durations: [Duration] = []
        for _ in 0..<PerfBudgets.onboardingIterations {
            let home = try FakeClaudeHome(isLive: isLive)
            homes.append(home)
            durations.append(try onboard(in: home))
        }
        let seconds = durations.map { $0 / .seconds(1) }
        let p95 = Measurement(value: try XCTUnwrap(seconds.percentile95()), unit: UnitDuration.seconds)
        check(p95, against: PerfBudgets.onboardingFirstToken,
              named: isLive ? "Onboarding con claude vera, p95" : "Onboarding con claude finta, p95",
              reportedAs: .onboardingFirstToken)

        // The same home after the onboarding: Bubo has its Sessione, and launches with no `claude`.
        guard let home = homes.last, !home.isLive else {
            recordSkipping(.claudeAfterOnboarding, because: "Solo con claude finta, che conta le proprie esecuzioni")
            return
        }
        let before = home.invocations.count
        let app = XCUIApplication.bubo(["-showsPanel", "NO"])
        app.launchEnvironment.merge(home.environment) { _, new in new }
        let launched = Date.now.timeIntervalSince1970
        app.launch()
        Thread.sleep(forTimeInterval: PerfBudgets.settleAfterLaunch)
        app.terminate()
        let runs = home.invocations.dropFirst(before)
        record(Double(runs.count), reportedAs: .claudeAfterOnboarding,
               from: "Esecuzioni di claude nei primi \(Int(PerfBudgets.settleAfterLaunch)) s, a onboarding completo")
        XCTAssertEqual(runs.count, PerfBudgets.claudeRunsAfterOnboarding,
                       "claude all'avvio a onboarding completo, lancio a \(launched): \(runs.joined(separator: " | "))")
    }

    /// Launches Bubo on `home` for the first time and does the onboarding's three actions: the recent Progetto, a
    /// suggested question, Invio.
    ///
    /// - Returns: The time from the launch to the first token, when the pill of `claude` leaves the HUD.
    @MainActor private func onboard(in home: FakeClaudeHome) throws -> Duration {
        let app = XCUIApplication.bubo(["-showsPanel", "NO", "-onboardingCompleted", "NO", "-AppleLanguages", "(it)"])
        app.launchEnvironment.merge(home.environment) { _, new in new }
        let clock = ContinuousClock()
        let launched = clock.now
        app.launch()
        defer { app.terminate() }

        let project = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", home.project.lastPathComponent))
            .firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 20), "Il Progetto recente non è comparso.")
        // The pill shows from the detection to the first token.
        let pill = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'claude '")).firstMatch
        XCTAssertTrue(pill.exists, "La pastiglia di claude non c'è.")
        project.click()
        let suggestion = app.buttons[Self.suggestion]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "La domanda suggerita non c'è.")
        suggestion.click()
        app.textFields["onboarding.prompt"].typeKey(.return, modifierFlags: [])

        let deadline = launched + .seconds(60)
        while pill.exists {
            guard clock.now < deadline else {
                XCTFail("Nessun primo token entro 60 s dal lancio.")
                break
            }
        }
        return launched.duration(to: clock.now)
    }
}
