import SwiftUI

/// The lines of the visore, numbered, scrolled to `target` with its row marked.
struct CodeLinesView: View {
    let lines: [CodeLine]
    /// The line the visore was opened on, from 1.
    let target: Int
    /// The index of the row in the middle of the view.
    @State private var position: Int?

    var body: some View {
        let digits = String(lines.count).count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    CodeLineRow(number: index + 1, digits: digits, line: lines[index], isTarget: index + 1 == target)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Spacing.xSmall)
        }
        .scrollPosition(id: $position, anchor: .center)
        .textSelection(.enabled)
        .onAppear { position = target - 1 }
        .onChange(of: target) { position = target - 1 }
    }
}

/// A line's number and its text, highlighted.
private struct CodeLineRow: View {
    let number: Int
    /// How many digits the longest line number has, so the numbers line up on the right.
    let digits: Int
    let line: CodeLine
    let isTarget: Bool

    var body: some View {
        let label = String(number)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(verbatim: String(repeating: " ", count: max(digits - label.count, 0)) + label)
                .foregroundStyle(isTarget ? Palette.textPrimary : Palette.textSecondary)
            Text(line.attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Typography.mono(size: 12))
        .padding(.horizontal, Spacing.small)
        .background(isTarget ? Palette.accent.opacity(0.08) : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Riga \(number): \(line.text)"))
        .accessibilityAddTraits(isTarget ? .isSelected : [])
    }
}
