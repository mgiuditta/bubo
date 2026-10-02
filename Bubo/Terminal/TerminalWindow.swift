import AppKit
import SwiftUI

/// The window the terminal panel goes to when it is detached from the HUD.
final class TerminalWindow {
    private let window: NSWindow
    private weak var store: TerminalStore?
    private var closing: (any NSObjectProtocol)?

    init(store: TerminalStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        window.contentViewController = NSHostingController(rootView: TerminalPanel(store: store, isInWindow: true))
        window.titlebarAppearsTransparent = true
        // Dark like the HUD it comes from, whatever the system appearance; the terminal's own colors are explicit.
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("Terminale") { window.center() }
        window.setFrameAutosaveName("Terminale")
        // Closing the window hides the panel; the shells keep running until ⌃` brings it back.
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                         queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.hide() }
        }
    }

    func show() {
        window.title = String(localized: "Terminale · \(store?.title ?? "")")
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}
