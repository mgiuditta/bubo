import XCTest

/// Runs Xcode's accessibility audit on every window Bubo shows: HUD, Settings and Panel.
///
/// Swift Testing cannot drive UI tests, so this suite uses XCTest.
nonisolated final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testHUDHasNoAccessibilityIssues() throws {
        let app = launchBubo(showingPanel: false)
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        try audit(app)
    }

    @MainActor func testSettingsHaveNoAccessibilityIssues() throws {
        let app = launchBubo(showingPanel: false)
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Le Impostazioni non si sono aperte.")
        try audit(app)
    }

    @MainActor func testUpdatesSettingsHaveNoAccessibilityIssues() throws {
        let app = launchBubo(showingPanel: false)
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Le Impostazioni non si sono aperte.")
        settings.toolbars.buttons["Aggiornamenti"].click()
        XCTAssertTrue(settings.checkBoxes["Ricevi le beta"].waitForExistence(timeout: 10), "Manca la scheda Aggiornamenti.")
        try audit(app)
    }

    /// "Controlla aggiornamenti…" is in the app menu, where VoiceOver reads it.
    @MainActor func testCheckForUpdatesIsInTheAppMenu() throws {
        let app = launchBubo(showingPanel: false)
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        XCTAssertTrue(app.menuBars.menuItems["Controlla aggiornamenti…"].exists, "Manca Controlla aggiornamenti….")
    }

    @MainActor func testPanelHasNoAccessibilityIssues() throws {
        let app = launchBubo(showingPanel: true)
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        // The Panel shows only while the HUD is closed.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.dialogs.buttons["Bubo"].waitForExistence(timeout: 10), "Il Panel non è comparso.")
        try audit(app)
    }

    /// The identifier of the HUD window, as SwiftUI names it after the scene id.
    private static let hudWindow = "hud"

    /// Launches Bubo with the Panel preference forced, so the user's settings do not matter.
    @MainActor private func launchBubo(showingPanel: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-showsPanel", showingPanel ? "YES" : "NO"]
        app.launch()
        return app
    }

    /// Audits everything on screen, ignoring only elements AppKit and SwiftUI own and give no way to fix.
    @MainActor private func audit(_ app: XCUIApplication) throws {
        let windowFrames = app.windows.allElementsBoundByIndex.map(\.frame)
        // Close, minimize and zoom: XCUITest names them `_XCUI:CloseWindow` and so on.
        let titleBarButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH '_XCUI:'"))
        let titleBarFrames = titleBarButtons.allElementsBoundByIndex.map(\.frame)
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            if titleBarFrames.contains(where: { $0.contains(element.frame) }) { return true }
            guard issue.auditType == .sufficientElementDescription else { return false }
            switch element.elementType {
            case .touchBar:
                // The Touch Bar AppKit gives every app, even on Macs without one.
                return true
            case .group:
                // The NSHostingView filling a window: SwiftUI gives it no label and no way to set one.
                return windowFrames.contains(element.frame)
            default:
                return false
            }
        }
    }
}
