import AppKit
import SwiftUI

/// The window of one Progetto's Galassia, resizable and free to go to another screen.
final class GalaxyWindow {
    /// The Galassia shown.
    let model: GalaxyModel
    private let window: NSWindow
    private var closing: (any NSObjectProtocol)?

    /// Creates the window of `model`, calling `onClose` when it closes.
    init(model: GalaxyModel, store: GalaxyStore, onClose: @escaping @MainActor () -> Void) {
        self.model = model
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        window.contentViewController = NSHostingController(rootView: GalaxyView(model: model, store: store))
        window.title = String(localized: "Galassia · \(model.project.lastPathComponent)")
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        if !window.setFrameUsingName("Galassia") { window.center() }
        window.setFrameAutosaveName("Galassia")
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                         queue: .main) { _ in
            MainActor.assumeIsolated { onClose() }
        }
    }

    isolated deinit {
        if let closing { NotificationCenter.default.removeObserver(closing) }
    }

    /// Brings the window forward.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
