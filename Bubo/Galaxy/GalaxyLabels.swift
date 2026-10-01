import SwiftUI

/// The names over the map: the comets, the selected file, the search results and the written files in view, and the
/// folders large enough to read.
///
/// Drawn in one canvas and hidden from VoiceOver: the list says the same.
struct GalaxyLabels: View {
    let model: GalaxyModel

    var body: some View {
        let labels = model.labels()
        Canvas { context, _ in
            for label in labels {
                context.draw(text(of: label), at: label.point, anchor: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func text(of label: GalaxyModel.Label) -> Text {
        let text = Text(verbatim: label.text)
        switch label.kind {
        case .folder:
            return text.font(Typography.body(size: 11)).foregroundStyle(Palette.textSecondary)
        case .file:
            return text.font(Typography.mono(size: 11, weight: .medium)).foregroundStyle(Palette.textPrimary)
        case let .comet(isWaiting):
            // Lume only for Attende te (ADR 0004).
            return text.font(Typography.body(size: 12, weight: .semibold))
                .foregroundStyle(isWaiting ? Palette.attention : Palette.textPrimary)
        }
    }
}
