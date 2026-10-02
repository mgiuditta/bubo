import AppKit
import SwiftUI

/// The bubble's window: a borderless, non-activating panel that takes the keyboard without activating Bubo, so the app
/// in front stays in front; esc calls `onCancel`.
final class PanelBubbleWindow: NSPanel {
    /// Called on esc.
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// Returns a bubble window showing `content`; its owner sizes it.
    static func make(content: some View) -> PanelBubbleWindow {
        let window = PanelBubbleWindow(contentRect: CGRect(x: 0, y: 0, width: PanelBubbleView.width, height: 1), styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: true)
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        // The Panel's elevation, the one place a shadow is allowed.
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        // Borderless windows have no title, so VoiceOver would announce a nameless window.
        window.setAccessibilityLabel(String(localized: "Domanda nel Panel"))
        let host = NSHostingView(rootView: content)
        // The content reports its size and the owner places the window: a bubble that opens upward keeps its bottom edge.
        host.sizingOptions = []
        window.contentView = host
        return window
    }
}
