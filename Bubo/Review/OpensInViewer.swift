import SwiftUI

/// A diff line that opens the visore at its line in the file after the change: ⌘-clic, as a path in the terminal,
/// the context menu and a VoiceOver action (spec 15). A plain clic stays free for the diff.
struct OpensInViewer: ViewModifier {
    let open: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .gesture(TapGesture().modifiers(.command).onEnded(open))
            .contextMenu {
                Button("Apri nel visore", systemImage: "doc.text.magnifyingglass", action: open)
            }
            .accessibilityAction(named: Text("Apri nel visore"), open)
    }
}

extension View {
    /// Opens the visore with `open` on ⌘-clic, from the context menu and from VoiceOver.
    func opensInViewer(_ open: @escaping () -> Void) -> some View {
        modifier(OpensInViewer(open: open))
    }
}
