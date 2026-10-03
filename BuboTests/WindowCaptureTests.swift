import CoreGraphics
import Foundation
import Testing
@testable import Bubo

/// «Allega finestra» (#485): the window under the cursor from CoreGraphics' list, and the name of its shot.
struct WindowCaptureTests {
    private static let bubo: pid_t = 100
    private static let safari = ScreenWindow(id: 1, processID: 200, appName: "Safari",
                                             frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0)
    private static let notes = ScreenWindow(id: 2, processID: 300, appName: "Note",
                                            frame: CGRect(x: 400, y: 300, width: 800, height: 600), layer: 0)
    private static let panel = ScreenWindow(id: 3, processID: bubo, appName: "Bubo",
                                            frame: CGRect(x: 500, y: 400, width: 100, height: 100), layer: 0)
    private static let menuBar = ScreenWindow(id: 4, processID: 400, appName: "Centro di Controllo",
                                              frame: CGRect(x: 0, y: 0, width: 1440, height: 24), layer: 25)

    @Test func theFrontmostWindowUnderThePointWins() {
        let windows = [Self.safari, Self.notes]

        #expect(ScreenWindow.frontmost(at: CGPoint(x: 500, y: 400), in: windows, excludingProcess: Self.bubo) == Self.safari)
        #expect(ScreenWindow.frontmost(at: CGPoint(x: 900, y: 700), in: windows, excludingProcess: Self.bubo) == Self.notes)
    }

    @Test func bubosOwnWindowsAndOtherLevelsAreSkipped() {
        let windows = [Self.menuBar, Self.panel, Self.notes]

        #expect(ScreenWindow.frontmost(at: CGPoint(x: 550, y: 450), in: windows, excludingProcess: Self.bubo) == Self.notes)
        #expect(ScreenWindow.frontmost(at: CGPoint(x: 450, y: 10), in: windows, excludingProcess: Self.bubo) == nil)
    }

    @Test func overTheDesktopThereIsNoWindow() {
        #expect(ScreenWindow.frontmost(at: CGPoint(x: 1300, y: 1000), in: [Self.safari, Self.notes],
                                       excludingProcess: Self.bubo) == nil)
    }

    @Test func theCursorIsFlippedToTheTopLeftOrigin() {
        #expect(ScreenWindow.point(fromScreenLocation: CGPoint(x: 10, y: 880), primaryScreenHeight: 900)
            == CGPoint(x: 10, y: 20))
    }

    @Test func anEntryOfTheWindowListIsRead() throws {
        let info: [String: Any] = [
            kCGWindowNumber as String: 52,
            kCGWindowOwnerPID as String: 200,
            kCGWindowOwnerName as String: "Safari",
            kCGWindowLayer as String: 0,
            kCGWindowBounds as String: CGRect(x: 10, y: 20, width: 300, height: 400).dictionaryRepresentation as NSDictionary,
        ]

        let window = try #require(ScreenWindow(info: info))

        #expect(window == ScreenWindow(id: 52, processID: 200, appName: "Safari",
                                       frame: CGRect(x: 10, y: 20, width: 300, height: 400), layer: 0))
        #expect(ScreenWindow(info: [kCGWindowNumber as String: 52]) == nil)
    }

    @Test func theShotIsNamedAfterItsApp() {
        // In the test host's language: «Finestra di Safari» in Italian, «Safari Window» in English.
        #expect(WindowCapture.fileName(forApp: "Safari").contains("Safari"))
        #expect(WindowCapture.fileName(forApp: "AC/DC: Live").contains("AC-DC- Live"))
        #expect(WindowCapture.fileName(forApp: "  ") == WindowCapture.fileName(forApp: nil))
        #expect(WindowCapture.fileName(forApp: nil) != WindowCapture.fileName(forApp: "Safari"))
    }
}
