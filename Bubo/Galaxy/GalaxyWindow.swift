import AppKit
import SwiftUI

/// The window of one Progetto's Galassia, resizable and free to go to another screen.
final class GalaxyWindow {
    /// The Galassia shown.
    let model: GalaxyModel
    private let window: NSWindow
    private var closing: (any NSObjectProtocol)?

    /// The size of the window the first time it opens.
    nonisolated static let defaultSize = CGSize(width: 1100, height: 720)
    /// The smallest the window gets: room for the map and the list side by side.
    nonisolated static let minimumSize = CGSize(width: 720, height: 480)
    /// The name the window's frame is saved under, so it opens where it was left.
    private static let frameName = "Galassia"

    /// Creates the window of `model`, calling `onClose` when it closes.
    init(model: GalaxyModel, store: GalaxyStore, onClose: @escaping @MainActor () -> Void) {
        self.model = model
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        let content = NSHostingController(rootView: GalaxyView(model: model, store: store)
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height))
        // SwiftUI gives the window only its minimum: with its ideal size too, the window shrank to a strip 600 by 130.
        content.sizingOptions = .minSize
        window.contentViewController = content
        window.setContentSize(Self.defaultSize)
        window.title = String(localized: "Galassia · \(model.project.lastPathComponent)")
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // Naming the frame also puts the window back where it was left, if it was.
        window.setFrameAutosaveName(Self.frameName)
        // A frame saved smaller than the minimum is that strip, saved before: such a window opens anew.
        let smallest = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumSize)).size
        if !window.setFrameUsingName(Self.frameName) || window.frame.width < smallest.width
            || window.frame.height < smallest.height {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
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
