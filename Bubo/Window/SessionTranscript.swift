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
            LazyVStack(alignment: .leading, spacing: Spacing.l) {
                ForEach(lines) { line in
                    Group {
                        if line.message.isFromUser {
                            UserBubble(text: line.message.text)
                        } else {
                            AnswerProse(prose: line.message.text)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("Claude")
                        }
                    }
                    .chatEntrance()
                }
                if let pendingPrompt {
                    UserBubble(text: pendingPrompt)
                        .chatEntrance()
                    // Where the answer will be, while the Sessione works on the turn.
                    ThinkingDots()
                        .chatEntrance()
                }
            }
            .animation(Motion.standard, value: lines.count)
            .animation(Motion.standard, value: pendingPrompt)
            .frame(maxWidth: Spacing.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Spacing.l)
        }
        // A chat opens on its last message, and stays there as new ones arrive.
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
