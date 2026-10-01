import AppKit
import SwiftUI

/// The visore's window, reused for every file it shows.
final class CodeViewerWindow {
    private let window: NSWindow
    private weak var store: CodeViewerStore?

    init(store: CodeViewerStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        window.contentViewController = NSHostingController(rootView: CodeViewer(store: store))
        window.titlebarAppearsTransparent = true
        // The visore is dark like the code it shows, whatever the system's appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("Visore") { window.center() }
        window.setFrameAutosaveName("Visore")
    }

    func show() {
        window.title = String(localized: "Visore · \(store?.location?.file.lastPathComponent ?? "")")
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
