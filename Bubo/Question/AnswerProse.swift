import SwiftUI

/// An answer as the conversation shows it: inline Markdown, with the notes cited as `[[nota]]` as links that open them,
/// and code in its own blocks.
struct AnswerProse: View {
    /// The answer without its Secondo cervello block, which never shows raw.
    let prose: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ForEach(Array(AnswerBlock.blocks(of: prose).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .prose(text):
                    Text(AnswerBlock.formatted(text))
                        .font(Typography.body(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                case let .code(code):
                    AnswerCodeBlock(code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
