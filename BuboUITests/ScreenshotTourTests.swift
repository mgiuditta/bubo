import AppKit
import XCTest

/// Takes a screenshot of every section of Bubo, in its main cases, as attachments named after the PNG to write.
///
/// Runs only with `TEST_RUNNER_BUBO_SCREENSHOT_TOUR=1` on the `xcodebuild` command line, so `check.sh` stays fast.
/// Nothing here has real effects: no Domanda is sent, no Sessione starts, nothing records; the preferences come from
/// launch arguments, which UserDefaults never persists.
nonisolated final class ScreenshotTourTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUBO_SCREENSHOT_TOUR"] == "1",
                          "Solo con BUBO_SCREENSHOT_TOUR=1")
        continueAfterFailure = true
    }

    // MARK: - Onboarding

    /// The first launch: with no Sessioni of the user's, `-onboardingCompleted NO` brings the steps back.
    @MainActor func test01Onboarding() {
        let app = launchBubo(["-onboardingCompleted", "NO"], fixture: false)
        defer { app.terminate() }
        let window = hud(app)
        snap("01-onboarding-01-avvio", window, after: 0.3)
        let line = app.descendants(matching: .any)["onboarding.orbLine"]
        guard line.waitForExistence(timeout: 10) else {
            // With Sessioni of their own the onboarding is over: nothing to show.
            snap("01-onboarding-00-non-mostrato", window)
            return
        }
        snap("01-onboarding-02-progetto-e-domanda", window, after: 4)
        // Choosing a recent Progetto only marks it: the Sessione starts at the question's ↩, never sent here.
        let openFolder = app.descendants(matching: .any)["onboarding.openFolder"]
        let recent = app.buttons.matching(NSPredicate(format: "label CONTAINS '/'")).firstMatch
        if recent.waitForExistence(timeout: 3) {
            recent.click()
            snap("01-onboarding-03-progetto-scelto", window)
        } else if openFolder.exists {
            snap("01-onboarding-03-nessun-progetto-recente", window)
        }
        let suggestion = app.buttons["Trova i TODO più vecchi"]
        if suggestion.exists {
            suggestion.click()
            snap("01-onboarding-04-domanda-scritta", window)
        }
    }

    // MARK: - Main window

    /// The window with the user's own data, as they see it.
    @MainActor func test02WindowWithTheUsersData() {
        let app = launchBubo([], fixture: false)
        defer { app.terminate() }
        tourSidebar(app, prefix: "02-finestra-reale")
    }

    /// The window with the fake Sessione «Login che scade» and the fake Domanda «Come funziona il router?».
    @MainActor func test03WindowWithTheFixture() {
        let app = launchBubo([], fixture: true)
        defer { app.terminate() }
        let window = hud(app)
        tourSidebar(app, prefix: "03-finestra-fixture")
        if select("bubo", in: app) { snap("03-finestra-fixture-05-progetto", window) }
        if select("Lavoro", in: app) { snap("03-finestra-fixture-06-lavoro-board", window) }
        if select("Come funziona il router?", in: app, prefix: true) { snap("03-finestra-fixture-07-domanda", window) }
        if select("Login che scade", in: app, prefix: true) { snap("03-finestra-fixture-08-sessione", window, after: 2) }
    }

    /// The 1.1 areas off, as a Release build has them: no Neuroni in the sidebar.
    @MainActor func test04WindowWithTheUnreleasedAreasOff() {
        let app = launchBubo([ "-debugHidesUnreleasedAreas", "YES"], fixture: true)
        defer { app.terminate() }
        snap("04-finestra-aree-1-1-spente", hud(app), after: 2)
    }

    // MARK: - Settings

    @MainActor func test05Settings() {
        let tabs = ["general", "appearance", "account", "permissions", "models", "budget", "machines", "voice",
                    "iPhone", "deliveries", "shortcuts", "updates", "diagnostics"]
        for (index, tab) in tabs.enumerated() {
            let app = launchBubo(["-settings.tab", tab], fixture: false)
            let window = settings(app)
            let name = String(format: "05-impostazioni-%02d-%@", index + 1, tab)
            snap(name, window, after: 2)
            // The long tabs go on below the 450 pt of the window.
            if Self.longSettingsTabs.contains(tab) {
                window.scroll(byDeltaX: 0, deltaY: -2000)
                snap("\(name)-fondo", window, after: 1)
            }
            app.terminate()
        }
    }

    /// The tabs taller than the window.
    private static let longSettingsTabs: Set<String> = ["general", "permissions", "models", "budget", "updates"]

    /// The Impostazioni of the 1.1 areas show «Arriverà presto» in a Release build.
    @MainActor func test06SettingsComingSoon() {
        for tab in ["machines", "iPhone", "deliveries"] {
            let app = launchBubo(["-settings.tab", tab, "-debugHidesUnreleasedAreas", "YES"], fixture: false)
            snap("06-impostazioni-arrivera-presto-\(tab)", settings(app), after: 2)
            app.terminate()
        }
    }

    // MARK: - Sheets

    @MainActor func test07Sheets() {
        let app = launchBubo([], fixture: true)
        defer { app.terminate() }
        let window = hud(app)
        // Each sheet is closed with Annulla, never confirmed.
        app.typeKey("n", modifierFlags: .command)
        snap("07-foglio-01-nuova-sessione", window, after: 1.5)
        cancelSheet(in: window)
        app.typeKey("n", modifierFlags: [.option, .command])
        snap("07-foglio-02-nuova-bozza", window, after: 1.5)
        cancelSheet(in: window)
        app.typeKey("i", modifierFlags: .command)
        snap("07-foglio-03-sessione-da-issue", window, after: 3)
        cancelSheet(in: window)
        // The foglio di Consegna needs a Sessione with a conversation and a worktree: only a real Sessione has them.
    }

    // MARK: - Panel

    @MainActor func test08Panel() {
        let app = launchBubo([], fixture: false, showsPanel: true)
        defer { app.terminate() }
        _ = hud(app)
        // The Panel shows only while the window is closed.
        app.typeKey("w", modifierFlags: .command)
        let panel = app.dialogs.firstMatch
        _ = panel.waitForExistence(timeout: 10)
        snapScreen("08-panel-01-chiuso", around: [panel], margin: 120, after: 2)
        if openStatusMenu(app) {
            let ask = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Chiedi nel Panel'")).firstMatch
            if ask.waitForExistence(timeout: 3) {
                ask.click()
                let bubble = app.descendants(matching: .any)["Domanda nel Panel"]
                snapScreen("08-panel-02-bolla-aperta", around: [panel, bubble], including: panel.frame.insetBy(dx: -480, dy: -320),
                           margin: 0, after: 2)
            }
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    // MARK: - Menus

    @MainActor func test09Menus() {
        let app = launchBubo([], fixture: true)
        defer { app.terminate() }
        _ = hud(app)
        if openStatusMenu(app) {
            let item = app.statusItems.firstMatch
            let below = CGRect(x: item.frame.minX - 320, y: item.frame.minY, width: 640, height: 760)
            snapScreen("09-menu-01-barra-dei-menu", around: [item], including: below, margin: 8, after: 1)
            app.typeKey(.escape, modifierFlags: [])
        }
        for (index, menu) in ["Bubo", "File", "Modifica", "Vista", "Finestra", "Aiuto"].enumerated() {
            let item = app.menuBars.menuBarItems[menu]
            guard item.exists else { continue }
            item.click()
            snapScreen(String(format: "09-menu-%02d-app-%@", index + 2, menu.lowercased()),
                       around: [item], including: CGRect(x: item.frame.minX, y: item.frame.minY, width: 480, height: 720),
                       margin: 8, after: 1)
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    // MARK: - Other windows

    @MainActor func test10Windows() {
        let app = launchBubo([], fixture: true)
        defer { app.terminate() }
        let window = hud(app)
        app.typeKey("k", modifierFlags: .command)
        let palette = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Cerca' AND (elementType == %d OR elementType == %d)", XCUIElement.ElementType.window.rawValue, XCUIElement.ElementType.dialog.rawValue)).firstMatch
        snapScreen("10-palette-01-vuota", around: [palette, window], margin: 24, after: 1.5)
        app.typeText("sess")
        snapScreen("10-palette-02-ricerca", around: [palette, window], margin: 24, after: 1.5)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        for (index, title) in ["Cronologia", "Costi", "Agenti", "Plugin", "Automazioni"].enumerated() {
            guard openFromWindowMenu(title, in: app) else { continue }
            let opened = app.windows.matching(NSPredicate(format: "title == %@", title)).firstMatch
            snap(String(format: "10-finestra-%02d-%@", index + 3, title.lowercased()), opened, after: 2.5)
            if title == "Automazioni" {
                let create = opened.buttons["Nuova Automazione"].firstMatch
                if create.exists {
                    create.click()
                    snap("10-finestra-08-automazione-foglio", opened, after: 1.5)
                    app.typeKey(.escape, modifierFlags: [])
                }
            }
        }

        // The Galassia shows the Progetto of the Sessione in front.
        window.click()
        if select("Login che scade", in: app, prefix: true) {
            app.typeKey("g", modifierFlags: [.option, .command])
            let galaxy = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Galassia'")).firstMatch
            _ = galaxy.waitForExistence(timeout: 5)
            snap("10-finestra-09-galassia", galaxy, after: 3)
        }
    }

    // MARK: - Debug

    @MainActor func test11DebugGallery() {
        let app = launchBubo([], fixture: false)
        defer { app.terminate() }
        _ = hud(app)
        guard openStatusMenu(app) else { return }
        let debug = app.menuItems["Debug Orb…"]
        guard debug.waitForExistence(timeout: 3) else {
            app.typeKey(.escape, modifierFlags: [])
            return
        }
        debug.click()
        let window = app.windows.matching(NSPredicate(format: "title == 'Debug Orb'")).firstMatch
        snap("11-debug-01-orb", window, after: 2)
        let gallery = window.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Galleria' OR title == 'Galleria'")).firstMatch
        if gallery.exists {
            gallery.click()
            snap("11-debug-02-galleria", window, after: 3)
        }
    }

    // MARK: - Appearance

    /// Bubo is only dark (ADR 0004): the light system appearance must change nothing.
    @MainActor func test12LightSystemAppearance() {
        let app = launchBubo(["-AppleInterfaceStyle", "Light", "-settings.tab", "general"], fixture: true,
                             showsPanel: true)
        defer { app.terminate() }
        let window = hud(app)
        snap("12-aspetto-chiaro-01-finestra", window, after: 2)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        _ = settings.waitForExistence(timeout: 10)
        snap("12-aspetto-chiaro-02-impostazioni", settings, after: 1.5)
        app.typeKey("w", modifierFlags: .command)
        window.click()
        app.typeKey("w", modifierFlags: .command)
        _ = app.dialogs.firstMatch.waitForExistence(timeout: 10)
        snapScreen("12-aspetto-chiaro-03-panel", around: [app.dialogs.firstMatch], margin: 120, after: 2)
    }

    // MARK: - Helpers

    /// Launches Bubo in Italian, with the Panel preference forced and, if asked, the fake Sessione and Domanda.
    @MainActor private func launchBubo(_ arguments: [String], fixture: Bool, showsPanel: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-showsPanel", showsPanel ? "YES" : "NO", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT",
                              // No window reopened from an earlier run, as the Plugin over the window.
                              "-ApplePersistenceIgnoreState", "YES"]
            + (fixture ? ["-sessions.fixture", "YES"] : []) + arguments
        app.launch()
        return app
    }

    /// The main window, once it is on screen.
    @MainActor private func hud(_ app: XCUIApplication) -> XCUIElement {
        let window = app.windows["hud"]
        XCTAssertTrue(window.waitForExistence(timeout: 15), "La finestra non è comparsa.")
        return window
    }

    /// The Impostazioni, opened with ⌘, on the tab of the launch arguments.
    @MainActor private func settings(_ app: XCUIApplication) -> XCUIElement {
        _ = hud(app)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Le Impostazioni non si sono aperte.")
        return settings
    }

    /// The home and the fixed entries of the sidebar: Cervello, Neuroni, Riunioni.
    @MainActor private func tourSidebar(_ app: XCUIApplication, prefix: String) {
        let window = hud(app)
        snap("\(prefix)-01-cervello-home", window, after: 3)
        if select("Neuroni", in: app) {
            snap("\(prefix)-02-neuroni", window, after: 3)
        } else {
            snap("\(prefix)-02-neuroni-assenti", window)
        }
        if select("Riunioni", in: app) {
            snap("\(prefix)-03-riunioni-a-subito", window, after: 0.5)
            // Without a Secondo cervello the Riunioni open its setup over them a moment later: closed, never answered.
            snap("\(prefix)-03-riunioni-b-dopo-3-secondi", window, after: 3)
            app.typeKey(.escape, modifierFlags: [])
        }
        if select("Cervello", in: app) { snap("\(prefix)-04-cervello-ritorno", window, after: 1) }
    }

    /// Clicks the sidebar row `text`; with `prefix`, the first row whose title starts with it.
    @MainActor private func select(_ text: String, in app: XCUIApplication, prefix: Bool = false) -> Bool {
        let predicate = prefix
            ? NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text, text)
            // A plain Label reads its title as its value; a Sessione's row has the title as label, its Progetto as value.
            : NSPredicate(format: "label == %@ OR (value == %@ AND label == '')", text, text)
        let row = app.outlines.descendants(matching: .any).matching(predicate).firstMatch
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("«\(text)» non è nella barra laterale.")
            return false
        }
        row.click()
        return true
    }

    /// Closes the sheet on `window` with its Annulla, and waits for it to go.
    @MainActor private func cancelSheet(in window: XCUIElement) {
        let sheet = window.sheets.firstMatch
        let cancel = sheet.buttons["Annulla"]
        if cancel.waitForExistence(timeout: 5) { cancel.click() }
        _ = sheet.waitForNonExistence(timeout: 5)
    }

    /// Opens the menu of Bubo's item in the menu bar.
    @MainActor private func openStatusMenu(_ app: XCUIApplication) -> Bool {
        let item = app.statusItems.firstMatch
        guard item.waitForExistence(timeout: 5) else {
            XCTFail("Manca la voce di Bubo nella barra dei menu.")
            return false
        }
        item.click()
        return true
    }

    /// Opens `title` from the Finestra menu.
    @MainActor private func openFromWindowMenu(_ title: String, in app: XCUIApplication) -> Bool {
        app.menuBars.menuBarItems["Finestra"].click()
        let item = app.menuBars.menuItems[title]
        guard item.waitForExistence(timeout: 3) else {
            app.typeKey(.escape, modifierFlags: [])
            XCTFail("Manca «\(title)» nel menu Finestra.")
            return false
        }
        item.click()
        return true
    }

    /// Attaches a screenshot named `name`: of `element` when it is on screen, of the whole screen otherwise.
    @MainActor private func snap(_ name: String, _ element: XCUIElement?, after delay: TimeInterval = 1) {
        pause(delay)
        let screenshot = if let element, element.exists, !element.frame.isEmpty {
            element.screenshot()
        } else {
            XCUIScreen.main.screenshot()
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Attaches a screenshot of the part of the screen around `elements`, so the rest of the desktop stays out; the
    /// whole screen when none of them is on screen.
    @MainActor private func snapScreen(_ name: String, around elements: [XCUIElement], including extra: CGRect? = nil,
                                       margin: CGFloat, after delay: TimeInterval = 1) {
        pause(delay)
        let screenshot = XCUIScreen.main.screenshot()
        let frames = elements.filter(\.exists).map(\.frame).filter { !$0.isEmpty } + (extra.map { [$0] } ?? [])
        let image = screenshot.image
        guard let region = frames.dropFirst().reduce(frames.first, { $0?.union($1) }),
              let whole = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            snap(name, nil, after: 0)
            return
        }
        // Frames are in points of the main screen, the screenshot in its pixels.
        let scale = CGFloat(whole.width) / (NSScreen.main?.frame.width ?? image.size.width)
        let crop = region.insetBy(dx: -margin, dy: -margin)
        let pixels = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale,
                            height: crop.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: whole.width, height: whole.height))
        guard let cropped = whole.cropping(to: pixels),
              let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
            snap(name, nil, after: 0)
            return
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Lets animations and loading settle; a screenshot has no element to wait for.
    @MainActor private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
