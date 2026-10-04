import XCTest

/// The sidebar of the main window opens a Sessione with the composer addressed to its Progetto (#701).
///
/// Bubo starts with fake Sessioni (`-sessions.fixture YES`, Debug only), never the user's.
nonisolated final class SessionSidebarTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testClickingASessionAddressesTheComposerToItsProject() {
        let app = XCUIApplication()
        // Italian whatever the Mac's language: the composer's chip reads «Destinatario: …».
        app.launchArguments = ["-showsPanel", "NO", "-sessions.fixture", "YES",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        defer { app.terminate() }

        let session = app.outlines.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Login che scade' OR value BEGINSWITH 'Login che scade'"))
            .firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10), "«Login che scade» non è nella barra laterale.")
        session.click()

        // A text on macOS reads its accessibility label as its value; the Domanda's chip says «Cervello» instead.
        let recipient = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'recipient' AND (label == 'Destinatario: bubo' OR value == 'Destinatario: bubo')"
        )).firstMatch
        XCTAssertTrue(recipient.waitForExistence(timeout: 10), "Il composer non mostra «Destinatario: bubo».")
    }
}
