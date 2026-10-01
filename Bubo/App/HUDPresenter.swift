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

    /// What the new Sessione sheet starts from.
    private(set) var sessionDraft = SessionDraft()

    /// Brings the HUD to the front with the new Sessione sheet (⌘N), filled in from `draft`.
    func createSession(from draft: SessionDraft = SessionDraft()) {
        sessionDraft = draft
        isCreatingSession = true
        show()
    }

    /// Whether the HUD is in front of the user: visible, key, with Bubo active.
    var isFrontmost: Bool {
        guard let window = hudWindow else { return false }
        return window.isVisible && window.isKeyWindow && NSApp.isActive
    }

    /// Brings the HUD to the front, or hides it if it is already frontmost.
    func toggle() {
        if isFrontmost {
            hudWindow?.orderOut(nil)
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
