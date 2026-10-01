import SwiftUI

/// The files of the revisione, each with a bar per blocco: accepted, rejected, undecided. A click goes to the
/// file's first undecided blocco.
struct ReviewFileList: View {
    let review: Review
    let decisions: [String: HunkDecision]
    /// The file of the blocco the keyboard acts on.
    let currentFile: Int?
    let select: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxSmall) {
                ForEach(Array(review.files.enumerated()), id: \.element.id) { index, file in
                    row(file, isCurrent: index == currentFile)
                }
            }
            .padding(Spacing.xSmall)
        }
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File")
    }

    private func row(_ file: ChangedFile, isCurrent: Bool) -> some View {
        let ids = file.hunks.map(\.id)
        let decided = ids.count { decisions[$0] != nil }
        return Button {
            select(ids.first { decisions[$0] == nil } ?? ids[0])
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: (file.path as NSString).lastPathComponent)
                        .font(Typography.body(size: 12.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Spacing.xxSmall)
                    Text(verbatim: "\(decided)/\(ids.count)")
                        .font(Typography.mono(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
                HStack(spacing: 2) {
                    ForEach(ids, id: \.self) { id in
                        Capsule()
                            .fill(Self.color(of: decisions[id]))
                            .frame(height: 3)
                    }
                }
            }
            .padding(Spacing.xSmall)
            .background(isCurrent ? Palette.lineStrong.opacity(0.4) : .clear, in: .rect(cornerRadius: CornerRadius.small))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(file.path)
        .accessibilityLabel(Text("\(file.path), \(decided) blocchi decisi su \(ids.count)"))
    }

    /// The color of a blocco's bar: accepted, rejected, undecided.
    static func color(of decision: HunkDecision?) -> Color {
        switch decision {
        case .accepted: Palette.success
        case .rejected: Palette.danger
        case nil: Palette.textFaint
        }
    }
}
