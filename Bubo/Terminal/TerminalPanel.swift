import SwiftUI

/// The terminal of a Sessione: its schede, + for a new one, and the terminal in front. A glass panel in the HUD,
/// or the whole of its own window once detached.
struct TerminalPanel: View {
    let store: TerminalStore
    /// Whether the panel fills the detached window instead of sitting in the HUD.
    var isInWindow = false

    private var sessionID: UUID? { store.session?.id }

    private var selected: TerminalTab? {
        guard let sessionID else { return nil }
        let tabs = store.tabs(of: sessionID)
        return tabs.first { $0.id == store.selection[sessionID] } ?? tabs.last
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
                .overlay(Palette.line)
            if let selected {
                TerminalHost(tab: selected)
                    .padding(Spacing.xxSmall)
            } else if let failure = store.failure {
                Text(verbatim: failure)
                    .font(Typography.body(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Terminale"))
    }

    private var bar: some View {
        HStack(spacing: Spacing.xxSmall) {
            if !isInWindow {
                Text(verbatim: store.title)
                    .font(Typography.body(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .padding(.trailing, Spacing.xSmall)
            }
            if let sessionID {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.xxSmall) {
                        ForEach(store.tabs(of: sessionID)) { tab in
                            TerminalTabButton(tab: tab, isSelected: tab.id == selected?.id) {
                                store.selection[sessionID] = tab.id
                            } close: {
                                store.close(tab, of: sessionID)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button("Nuova scheda", systemImage: "plus", action: store.openTab)
                .help("Apre un'altra shell nella cartella della Sessione")
            Spacer(minLength: Spacing.xSmall)
            if isInWindow {
                Button("Riporta nell'HUD", systemImage: "rectangle.bottomhalf.inset.filled") {
                    store.setDetached(false)
                }
                .help("Riporta il terminale nell'HUD")
            } else {
                Button("Stacca in una finestra", systemImage: "macwindow.on.rectangle") {
                    store.setDetached(true)
                }
                .help("Sposta il terminale in una finestra sua")
                Button("Nascondi il terminale", systemImage: "chevron.down", action: store.hide)
                    .help("Nasconde il terminale; le shell restano aperte")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.small)
        // Room for the window's buttons when the bar sits under its transparent title bar.
        .padding(.top, isInWindow ? 28 : Spacing.xSmall)
        .padding(.bottom, Spacing.xSmall)
    }
}

/// A scheda's name, which brings it to the front, and its ×.
private struct TerminalTabButton: View {
    let tab: TerminalTab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xxSmall) {
            Button(action: select) {
                Text(verbatim: tab.title)
                    .font(Typography.mono(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button("Chiudi la scheda", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .help("Chiude la shell e quello che vi è in esecuzione")
        }
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, 3)
        .background(isSelected ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.small))
    }
}
