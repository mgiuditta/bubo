import SwiftUI

/// A line of the continuous diff: added on success, removed on danger, faint once its blocco is decided.
struct DiffLineRow: View {
    let line: Hunk.Line
    let isDecided: Bool
    /// The size of the text: larger in Focus.
    var size: CGFloat = 12

    var body: some View {
        Text(verbatim: mark + line.text)
            .font(Typography.mono(size: size))
            .foregroundStyle(line.kind == .context ? Palette.textSecondary : Palette.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.small)
            .background(background)
            .opacity(isDecided ? 0.55 : 1)
            .accessibilityLabel(spoken)
    }

    private var mark: String {
        switch line.kind {
        case .context: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private var background: Color {
        switch line.kind {
        case .context: .clear
        case .added: Palette.success.opacity(0.08)
        case .removed: Palette.danger.opacity(0.09)
        }
    }

    private var spoken: Text {
        switch line.kind {
        case .context: Text(verbatim: line.text)
        case .added: Text("Aggiunta: \(line.text)")
        case .removed: Text("Rimossa: \(line.text)")
        }
    }
}
