import AppKit
import SwiftUI

/// A block of code in an answer: monospaced on the surface, with its own Copia that copies the block alone.
struct AnswerCodeBlock: View {
    let code: String

    var body: some View {
        Text(code)
            .font(Typography.mono(size: 12))
            .foregroundStyle(Palette.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.xSmall)
            .padding(.trailing, Spacing.medium)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.small))
            .overlay(alignment: .topTrailing) {
                Button("Copia il codice", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .padding(Spacing.xxSmall)
                .help("Copia il codice")
                .accessibilityIdentifier("question.copyCode")
            }
    }
}
