import SwiftUI

/// The conversation of a Sessione as a chat: its messages in order, the newest at the bottom, and what was just sent
/// until its turn ends; no search, no highlighted point.
struct SessionTranscript: View {
    /// The messages read so far; empty before the first turn ends.
    let lines: [TranscriptLine]
    /// What the user sent for the turn in progress, not in ``lines`` yet; `nil` for none.
    let pendingPrompt: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(lines) { line in
                    TranscriptLineView(line: line, words: [], isCurrent: false)
                }
                if let pendingPrompt {
                    PendingPrompt(text: pendingPrompt)
                }
            }
            .frame(maxWidth: Spacing.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Spacing.l)
        }
        // A chat opens on its last message, and stays there as new ones arrive.
        .defaultScrollAnchor(.bottom)
    }
}

/// What the user just sent, as their message, while the Sessione works on it.
private struct PendingPrompt: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(spacing: Spacing.xSmall) {
                Text("Tu")
                    .foregroundStyle(Palette.textSecondary)
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Sta lavorando")
            }
            .font(Typography.mono(size: 10, weight: .medium))
            .textCase(.uppercase)
            Text(verbatim: text)
                .font(Typography.body(size: 13))
                .textSelection(.enabled)
        }
        .padding(Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
