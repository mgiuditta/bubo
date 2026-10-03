import SwiftUI

/// A note in the Neuroni's list: the color of its folder, its name, under it its folder, and how many notes it is
/// linked with.
struct NeuronRow: View {
    let note: NeuronGraph.Note
    /// The color of its folder, as `0xRRGGBB`.
    let color: UInt32
    /// Whether the last answer cited it.
    let isCited: Bool

    var body: some View {
        HStack(spacing: Spacing.xxSmall) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: note.name)
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textPrimary)
                if !note.parent.isEmpty {
                    Text(verbatim: note.parent)
                        .font(Typography.mono(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            if isCited {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel("Citata nell'ultima risposta")
                    .help("Citata nell'ultima risposta")
            }
            Text("\(note.degree) collegamenti")
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
