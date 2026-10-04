import AppKit
import SwiftUI

/// The Cronologia window, outside the HUD like the Costi one: opened from the Finestra menu and from the Palette, on the
/// message found. It has no Orb, so only one Orb stays on screen.
final class HistoryWindow {
    private let model: HistoryModel
    private lazy var window = makeWindow()

    /// Creates the window, built at its first opening.
    ///
    /// - Parameters:
    ///   - search: Makes the search over the current Sessioni and Cronologia CLI.
    ///   - read: Reads every message of a conversation, from `~/.claude` or from Bubo's copy.
    ///   - actions: Riprendi and Continua da qui on the conversation read.
    init(search: @escaping () -> ConversationSearch,
         read: @escaping (String) async throws -> [CLIConversation.Message], actions: ResumeActions) {
        model = HistoryModel(search: search, read: read, actions: actions)
    }

    /// Shows the window as it was left: the Finestra menu.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows the window on `result`, found by searching `text`: ↩ in the Palette.
    func show(_ result: ConversationResult, searching text: String) {
        model.open(result, searching: text)
        show()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_160, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = String(localized: "Cronologia")
        window.contentViewController = NSHostingController(rootView: HistoryView(model: model))
        // Dark like the rest of Bubo, whatever the system's appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // The Finestra menu already has its own Cronologia item, which also opens it when closed.
        window.isExcludedFromWindowsMenu = true
        if !window.setFrameUsingName("Cronologia") { window.center() }
        window.setFrameAutosaveName("Cronologia")
        return window
    }
}
