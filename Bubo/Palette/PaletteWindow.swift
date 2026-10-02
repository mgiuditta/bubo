import AppKit
import SwiftUI

/// The Palette's window: a panel that takes the keyboard, opened with ⌘K over the Bubo window in front, the HUD or the
/// Panel; it closes with esc, when a conversation opens, or when another window takes the keyboard.
final class PaletteWindow: NSObject, NSWindowDelegate {
    /// The Palette's size, in points.
    static let size = CGSize(width: 780, height: 480)

    private let model: PaletteModel
    private lazy var panel = makePanel()

    /// Creates the Palette, built at its first opening.
    ///
    /// - Parameters:
    ///   - search: Makes the search over the current Sessioni and Cronologia CLI.
    ///   - actions: Riprendi (⌥↩) and Continua da qui (⌘↩) on the chosen conversation.
    ///   - open: Opens a conversation, read only, after the Palette closes.
    init(search: @escaping () -> ConversationSearch, actions: ResumeActions,
         open: @escaping (ConversationResult) -> Void) {
        var close: () -> Void = {}
        model = PaletteModel(search: search) { result in
            close()
            open(result)
        }
        super.init()
        close = { [weak self] in self?.close() }
        model.close = close
        model.actions = actions
    }

    /// The words searched in the box, without the gettoni.
    var searchedText: String { model.query.search.text }

    /// Whether the Palette is on screen.
    var isShown: Bool { panel.isVisible }

    /// Shows the Palette with an empty box, or closes it if it is shown: ⌘K.
    func toggle() {
        isShown ? close() : show()
    }

    /// Shows the Palette over the Bubo window in front, with `text` in its box.
    func show(text: String = "") {
        let anchor = Self.frontWindow(excluding: panel)
        let screen = anchor?.screen ?? NSScreen.main
        if let screen {
            let frame = Self.frame(of: Self.size, over: anchor?.frame ?? screen.visibleFrame, in: screen.visibleFrame)
            panel.setFrame(frame, display: false)
        }
        var query = PaletteQuery()
        query.text = text
        query.absorbFilters()
        model.query = query
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Searches again, as when the Sessioni or the Cronologia CLI changed.
    func refresh() async {
        await model.refresh()
    }

    /// Closes the Palette.
    func close() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Where the Palette goes: centred on `anchor`, near its top when it is tall enough, else over its centre; inside
    /// `screen`.
    static func frame(of size: CGSize, over anchor: CGRect, in screen: CGRect) -> CGRect {
        let top = anchor.maxY - anchor.height * 0.15
        var origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: top - size.height >= anchor.minY ? top - size.height : anchor.midY - size.height / 2)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    /// The Bubo window in front: the key one, else the main one, else the Panel.
    private static func frontWindow(excluding palette: NSWindow) -> NSWindow? {
        let visible = NSApp.orderedWindows.filter { $0 !== palette && $0.isVisible }
        return visible.first(where: \.isKeyWindow) ?? visible.first(where: \.isMainWindow)
            ?? visible.first { $0.level == .floating }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless],
                             backing: .buffered, defer: true)
        // Above the Panel, which floats.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        // Borderless windows have no title, so VoiceOver would announce a nameless window.
        panel.setAccessibilityLabel(String(localized: "Cerca"))
        panel.contentView = NSHostingView(rootView: PaletteView(model: model))
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }
}

/// A borderless panel that can take the keyboard, which a borderless window cannot by default; esc calls `onCancel`.
private final class KeyPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
