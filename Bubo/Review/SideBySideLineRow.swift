import SwiftUI

/// A row of the side-by-side diff: the line before on the left, the line after on the right.
struct SideBySideLineRow: View {
    let pair: Hunk.Pair
    let isDecided: Bool

    var body: some View {
        HStack(spacing: 0) {
            half(pair.before)
            Divider()
            half(pair.after)
                // An unchanged line is on both sides: VoiceOver reads it once.
                .accessibilityHidden(pair.after?.kind == .context)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func half(_ line: Hunk.Line?) -> some View {
        if let line {
            DiffLineRow(line: line, isDecided: isDecided)
        } else {
            DiffLineRow(line: Hunk.Line(kind: .context, text: ""), isDecided: isDecided)
                .accessibilityHidden(true)
        }
    }
}
