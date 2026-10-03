import AppKit
import SwiftUI

/// The window of the Riunioni, outside the HUD: opened from the menu bar, the Orb's menu, the Palette and Siri.
final class MeetingWindow {
    private let recorder: MeetingRecorder
    private lazy var window = makeWindow()

    /// Creates the window of `recorder`, built at its first opening.
    init(recorder: MeetingRecorder) {
        self.recorder = recorder
    }

    /// Brings the window forward.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MeetingView(recorder: recorder)))
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "Riunione")
        // Dark like the rest of Bubo, whatever the system's appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
