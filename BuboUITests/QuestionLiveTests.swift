import XCTest

/// A real Domanda through the bundled bridge and the user's `claude`: needs a login and the network.
///
/// Runs only with `TEST_RUNNER_BUBO_LIVE=1` on the `xcodebuild` command line.
nonisolated final class QuestionLiveTests: XCTestCase {
    @MainActor func testAQuestionStreamsAnAnswerIntoTheHUD() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUBO_LIVE"] == "1", "Solo con BUBO_LIVE=1")
        let app = XCUIApplication()
        app.launchArguments = ["-showsPanel", "NO"]
        app.launch()
        defer { app.terminate() }

        let prompt = app.textFields["question.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "Il campo della Domanda non è comparso.")
        prompt.click()
        prompt.typeText("Rispondi solo con la parola: pronto\n")

        let answer = app.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] 'pronto' OR label CONTAINS[c] 'pronto'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60), "Nessuna risposta nell'HUD.")
    }
}
