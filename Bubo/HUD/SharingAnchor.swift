import AppKit
import SwiftUI

/// An empty AppKit view behind a SwiftUI control, for AppKit menus that need a view to show next to, such as the
/// Condividi of macOS.
struct SharingAnchor: NSViewRepresentable {
    /// Receives the view once it exists.
    let found: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in found(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
