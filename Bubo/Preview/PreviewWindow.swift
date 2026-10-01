import AppKit
import SwiftUI

/// The window the Anteprima's panel goes to when it is detached from the HUD.
final class PreviewWindow {
    private let window: NSWindow
    private weak var store: PreviewStore?
    private var closing: (any NSObjectProtocol)?

    init(store: PreviewStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_024, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        window.contentViewController = NSHostingController(rootView: PreviewPanel(store: store, isInWindow: true))
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("Anteprima") { window.center() }
        window.setFrameAutosaveName("Anteprima")
        // Closing the window hides the panel; the page stays open until the panel comes back.
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                         queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.hide() }
        }
    }

    func show() {
        window.title = String(localized: "Anteprima · \(store?.title ?? "")")
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}
