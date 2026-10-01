import AppKit
import SwiftUI

/// Shows and hides the HUD window from anywhere, including the global shortcut.
@Observable
final class HUDPresenter {
    /// The id of the HUD `Window` scene.
    static let windowID = "hud"

    /// Captured from the first SwiftUI view that appears, since AppKit code has
    /// no environment of its own.
    @ObservationIgnored var openWindow: OpenWindowAction?

    /// Whether the HUD shows the new Sessione sheet.
    var isCreatingSession = false

    /// Brings the HUD to the front with the new Sessione sheet (⌘N).
    func createSession() {
        isCreatingSession = true
        show()
    }

    /// Brings the HUD to the front, or hides it if it is already frontmost.
    func toggle() {
        if let window = hudWindow, window.isVisible, window.isKeyWindow, NSApp.isActive {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    /// Brings the HUD to the front, creating it if it was closed.
    func show() {
        NSApp.activate()
        if let window = hudWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: Self.windowID)
        }
    }

    private var hudWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(Self.windowID) == true }
    }
}
