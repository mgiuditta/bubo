import AppKit
import SwiftTerm
import SwiftUI

/// A scheda of a Sessione's terminal: SwiftTerm's view on a pseudo-terminal of Bubo's own (spec 15).
///
/// SwiftTerm only draws and reads the keyboard; the shell and its terminal belong to ``PTYSession``. The scrollback
/// lives in the view and is never saved.
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()
    /// What the shell put in the title, else its name.
    private(set) var title: String
    /// The view, moved between the HUD and the detached window with its scrollback.
    @ObservationIgnored let view: TerminalView
    @ObservationIgnored let pty: PTYSession
    /// Called when a command may have started or stopped a server: a Return typed, a `localhost` URL or an OSC 133
    /// mark in the output.
    @ObservationIgnored private let onServerHint: () -> Void

    /// How many lines each scheda keeps above the screen: with ten Sessioni, a few MB each at most.
    static let scrollback = 5_000

    /// Starts a scheda with the login shell in `folder`, or with `shell` and `arguments` when given.
    ///
    /// - Parameters:
    ///   - onServerHint: Called on the main thread when a Return is typed or the output hints that a server started
    ///     or stopped.
    ///   - onExit: Called on the main thread when the shell exits.
    /// - Throws: ``ProcessSpawnerError`` when the shell cannot start.
    init(folder: URL, environment: [String: String], shell: URL = PTYSession.loginShell,
         arguments: [String] = ["-l"], onServerHint: @escaping () -> Void = {},
         onExit: @escaping (TerminalTab) -> Void) throws {
        let font = NSFont(name: "JetBrains Mono", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        view = TerminalView(frame: .zero, font: font, options: TerminalOptions(scrollback: Self.scrollback))
        let terminal = view.getTerminal()
        pty = try PTYSession(folder: folder, environment: environment, shell: shell, arguments: arguments,
                             columns: terminal.cols, rows: terminal.rows)
        title = shell.lastPathComponent
        self.onServerHint = onServerHint
        view.terminalDelegate = self
        view.nativeForegroundColor = NSColor(Palette.textPrimary)
        view.nativeBackgroundColor = NSColor(Palette.ink)
        view.backgroundOpacity = 0.55
        view.caretColor = NSColor(Palette.accent)
        // ⌥ writes the characters of the Italian keyboard (@ # [ ] { }) instead of acting as Meta.
        view.optionAsMetaKey = false
        view.setAccessibilityLabel(String(localized: "Terminale"))
        pty.onOutput = { [weak view] bytes in
            view?.feed(byteArray: bytes)
            if CommandMarks.hintsAtServer(bytes) { onServerHint() }
        }
        pty.onExit = { [weak self] in
            guard let self else { return }
            onExit(self)
        }
    }
}

extension TerminalTab: @preconcurrency TerminalViewDelegate {
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        pty.resize(columns: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        if !title.isEmpty { self.title = title }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        pty.write(data)
        // A command starts: zsh and bash write no OSC 133 without an integration Bubo does not inject yet.
        if data.contains(UInt8(ascii: "\r")) { onServerHint() }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
