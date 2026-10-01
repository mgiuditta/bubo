import SwiftUI

/// The terminal and, next to it, the Anteprima, each in a glass panel, when they show in the HUD.
struct PanelRow: View {
    let terminals: TerminalStore
    let previews: PreviewStore

    var body: some View {
        let showsTerminal = terminals.isShown && !terminals.isDetached
        let showsPreview = previews.isShown && !previews.isDetached && previews.shown != nil
        if showsTerminal || showsPreview {
            HStack(spacing: Spacing.small) {
                if showsTerminal {
                    TerminalPanel(store: terminals)
                        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
                }
                if showsPreview {
                    PreviewPanel(store: previews)
                        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
                }
            }
            // Taller with the Anteprima, for a page to read.
            .frame(height: showsPreview ? 360 : 280)
        }
    }
}
