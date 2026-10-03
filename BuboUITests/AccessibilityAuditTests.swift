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
        // The tab is preselected: at 480 pt Aggiornamenti sits in the toolbar's overflow menu.
        let app = launchBubo(showingPanel: false, settingsTab: "updates")
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Le Impostazioni non si sono aperte.")
        XCTAssertTrue(settings.descendants(matching: .any)["Ricevi le beta"].waitForExistence(timeout: 10), "Manca la scheda Aggiornamenti.")
        try audit(app)
    }

    /// "Controlla aggiornamenti…" is in the app menu, where VoiceOver reads it.
    @MainActor func testCheckForUpdatesIsInTheAppMenu() throws {
        let app = launchBubo(showingPanel: false)
        defer { app.terminate() }
        XCTAssertTrue(app.windows[Self.hudWindow].waitForExistence(timeout: 10), "L'HUD non è comparso.")
        // A submenu's items reach the accessibility tree only while it is open.
        app.menuBars.menuBarItems["Bubo"].click()
        XCTAssertTrue(app.menuBars.menuItems["Controlla aggiornamenti…"].waitForExistence(timeout: 5),
                      "Manca Controlla aggiornamenti….")
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
    @MainActor private func launchBubo(showingPanel: Bool, settingsTab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Italian whatever the Mac's language: the tests look elements up by their Italian titles.
        app.launchArguments = ["-showsPanel", showingPanel ? "YES" : "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        if let settingsTab { app.launchArguments += ["-settings.tab", settingsTab] }
        app.launch()
        return app
    }

    /// Audits everything on screen, ignoring only elements AppKit and SwiftUI own and give no way to fix.
    @MainActor private func audit(_ app: XCUIApplication) throws {
        let windowFrames = app.windows.allElementsBoundByIndex.map(\.frame)
        // Close, minimize and zoom: XCUITest names them `_XCUI:CloseWindow` and so on.
        let titleBarButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH '_XCUI:'"))
        let titleBarFrames = titleBarButtons.allElementsBoundByIndex.map(\.frame)
        // ponytail: contrast is left out. On the HUD's and Settings' translucent windows the audit samples the desktop
        // behind them and fails white-on-dark text; token contrast is checked by PaletteContrastTests instead.
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            guard let element = issue.element else { return false }
            if titleBarFrames.contains(where: { $0.contains(element.frame) }) { return true }
            guard issue.auditType == .sufficientElementDescription else { return false }
            switch element.elementType {
            case .popUpButton:
                // AppKit's toolbar overflow chevron in Settings («ulteriori elementi della barra strumenti»).
                return element.label == "ulteriori elementi della barra strumenti"
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
