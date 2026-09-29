import AppKit
import SwiftUI

/// A button that records the next key combination pressed.
///
/// Esc cancels; combinations without ⌘, ⌥ or ⌃ are ignored.
struct ShortcutRecorder: View {
    /// The shortcut shown when not recording.
    let shortcut: KeyShortcut
    /// Called with the recorded shortcut.
    let onRecord: (KeyShortcut) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? String(localized: "Premi la combinazione…") : shortcut.displayName) {
            isRecording ? stopRecording() : startRecording()
        }
        .font(Typography.mono(size: 12))
        .accessibilityHint("Registra una nuova scorciatoia. Esc annulla.")
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
            } else if let recorded = KeyShortcut(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                characters: event.charactersIgnoringModifiers
            ) {
                onRecord(recorded)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
