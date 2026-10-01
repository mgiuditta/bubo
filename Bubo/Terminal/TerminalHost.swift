import AppKit
import SwiftUI

/// Puts a scheda's terminal view in SwiftUI, taking it from wherever it was so its scrollback comes along, and
/// gives it the keyboard.
struct TerminalHost: NSViewRepresentable {
    let tab: TerminalTab

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        let view = tab.view
        guard view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        // Once the container is in its window.
        Task { view.window?.makeFirstResponder(view) }
    }
}
