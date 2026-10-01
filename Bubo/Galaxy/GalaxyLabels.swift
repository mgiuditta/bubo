import SwiftUI

/// The names over the map: the selected file, the search results in view and the folders large enough to read.
///
/// Drawn in one canvas and hidden from VoiceOver: the list says the same.
struct GalaxyLabels: View {
    let model: GalaxyModel

    var body: some View {
        let labels = model.labels()
        Canvas { context, _ in
            for label in labels {
                let text = Text(verbatim: label.text)
                    .font(label.isFile ? Typography.mono(size: 11, weight: .medium) : Typography.body(size: 11))
                    .foregroundStyle(label.isFile ? Palette.textPrimary : Palette.textSecondary)
                context.draw(text, at: label.point, anchor: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
