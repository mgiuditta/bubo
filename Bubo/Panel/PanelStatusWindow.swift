import AppKit
import SwiftUI

/// The status pill's window: a borderless, non-activating panel that never takes the keyboard, so a click on the pill
/// leaves the app in front where it is until the HUD or the bubble opens.
final class PanelStatusWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Returns a pill window showing `content`; its owner sizes and places it.
    static func make(content: some View) -> PanelStatusWindow {
        let window = PanelStatusWindow(contentRect: CGRect(x: 0, y: 0, width: 1, height: PanelStatusLayout.height),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        // Borderless windows have no title, so VoiceOver would announce a nameless window.
        window.setAccessibilityLabel(String(localized: "Stato del Panel"))
        let host = FirstClickHostingView(rootView: content)
        host.sizingOptions = []
        window.contentView = host
        return window
    }
}

/// A hosting view whose first click reaches the pill, though Bubo is not the active app.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
