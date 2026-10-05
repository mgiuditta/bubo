import SwiftUI

/// The live Orb over a chat, small: the one who answers is there in every conversation, not only in the empty home.
struct ChatOrb: View {
    var body: some View {
        HUDOrb()
            .frame(width: 88, height: 88)
            .frame(maxWidth: .infinity)
    }
}

/// What the user wrote: on the right, on the quiet surface of the panels, so the answers read apart from it.
struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: Spacing.xxl)
            Text(verbatim: text)
                .font(.buboBody)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
                .overlay(RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tu")
    }
}

/// Where the answer will be, while it has not started: three dots that pulse, as a chat does.
struct ThinkingDots: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.buboTitle)
            .foregroundStyle(Palette.textSecondary)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
            .padding(.vertical, Spacing.xxs)
            .accessibilityLabel("Sto pensando…")
    }
}

extension View {
    /// A new message of a chat comes in from a little below, fading in; with Riduci movimento, only the fade.
    func chatEntrance() -> some View {
        transition(Motion.isReduced ? .opacity : .opacity.combined(with: .offset(y: Spacing.s)))
    }
}
