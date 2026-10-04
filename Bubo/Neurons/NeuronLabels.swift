import SwiftUI

/// The names over the map: the selected note, the cited ones, the search results and the most linked notes in view.
///
/// Drawn in one canvas and hidden from VoiceOver: the list says the same.
struct NeuronLabels: View {
    let model: NeuronModel

    var body: some View {
        let labels = model.labels()
        Canvas { context, _ in
            for label in labels {
                let text = Text(verbatim: label.text)
                    .font(Typography.body(size: 11, weight: label.isStrong ? .semibold : .regular))
                    .foregroundStyle(label.isStrong ? Palette.textPrimary : Palette.textSecondary)
                context.draw(text, at: label.point, anchor: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
