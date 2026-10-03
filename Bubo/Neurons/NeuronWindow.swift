import AppKit
import SwiftUI

/// The window of the Neuroni, resizable and free to go to another screen.
final class NeuronWindow {
    /// The Neuroni shown.
    let model: NeuronModel
    private let window: NSWindow
    private var closing: (any NSObjectProtocol)?

    /// The name the window's frame is saved under, so it opens where it was left.
    private static let frameName = "Neuroni"

    /// Creates the window of `model`, ringing the notes cited in the last answer of `questions`, and calling `onClose` when it closes.
    init(model: NeuronModel, questions: QuestionModel, onClose: @escaping @MainActor () -> Void) {
        self.model = model
        window = NSWindow(contentRect: NSRect(origin: .zero, size: GalaxyWindow.defaultSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        let content = NSHostingController(rootView: NeuronView(model: model, questions: questions)
            .frame(minWidth: GalaxyWindow.minimumSize.width, minHeight: GalaxyWindow.minimumSize.height))
        // As the Galassia: with its ideal size too, SwiftUI would shrink the window to a strip.
        content.sizingOptions = .minSize
        window.contentViewController = content
        window.setContentSize(GalaxyWindow.defaultSize)
        window.title = String(localized: "Neuroni · \(model.secondBrain.name)")
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        if !window.setFrameAutosaveName(Self.frameName) || !window.setFrameUsingName(Self.frameName) {
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
