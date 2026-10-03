import SwiftUI

/// The status pill beside the reduced Orb: a short text, with the Lume dot for Attende te, that a click follows.
///
/// Achromatic glass (ADR 0004); opaque graphite with Riduci trasparenza or Aumenta contrasto, where the glass could let
/// a bright desktop through behind the text.
struct PanelStatusView: View {
    let panel: OrbPanelController
    /// Called on a click, with what the pill said.
    let onPress: (PanelStatus) -> Void
    /// Called with the content's size whenever it changes, to fit the window around it.
    var onResize: (CGSize) -> Void = { _ in }

    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if let status = panel.status {
                pill(status)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: \.size, action: onResize)
                    .transition(transition)
            }
        }
        .animation(panel.statusAppearance == .grow ? Motion.emphasized : Motion.quick, value: panel.status)
    }

    private var transition: AnyTransition {
        switch panel.statusAppearance {
        case .grow: .scale(scale: 0.9, anchor: panel.zone.statusSide.anchor).combined(with: .opacity)
        case .fade: .opacity
        }
    }

    private var isOpaque: Bool { reducesTransparency || contrast == .increased }

    private func pill(_ status: PanelStatus) -> some View {
        Button {
            onPress(status)
        } label: {
            HStack(spacing: Spacing.xxSmall + 2) {
                if status.showsLume {
                    // Never the only cue: the text says the same.
                    Circle()
                        .fill(Palette.attention)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(verbatim: status.text)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.small - 2)
            .frame(minWidth: 28, minHeight: PanelStatusLayout.height)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background {
            if isOpaque { Capsule().fill(Palette.ink) }
        }
        .glassEffect(isOpaque ? .identity : .regular.interactive(), in: .capsule)
        .overlay {
            Capsule().strokeBorder(isOpaque ? Palette.lineStrong : Palette.line)
        }
        .help(status.help)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityIdentifier("panel.status")
    }
}

#Preview {
    PanelStatusView(panel: OrbPanelController(), onPress: { _ in })
        .padding()
}
