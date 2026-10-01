import SwiftUI

/// One conversation in the Palette: the message that answers best, with who wrote it, then the title, the fonte,
/// the Progetto, when, and how many other messages answer.
struct PaletteResultRow: View {
    let result: ConversationResult
    let words: [String]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            // The fragment before the title: many titles are only the first prompt.
            if let best = result.best {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    author(of: best)
                    HighlightedText(text: MatchHighlight.excerpt(of: best.text, matching: words), words: words)
                        .font(Typography.body(size: 13))
                        .lineLimit(2)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(verbatim: result.title)
                    .font(Typography.body(size: result.best == nil ? 13 : 12, weight: .semibold))
                    .foregroundStyle(result.best == nil ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                Text(verbatim: details)
                    .font(Typography.mono(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.medium))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: CornerRadius.medium).strokeBorder(Palette.lineStrong)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func author(of hit: SearchHit) -> some View {
        Text(hit.message?.isFromUser == true ? "Tu" : "Claude")
            .font(Typography.mono(size: 10, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(Palette.textSecondary)
    }

    /// Fonte · Progetto · when · +N altri messaggi.
    private var details: String {
        [result.source == .session ? String(localized: "Sessione") : String(localized: "CLI"),
         result.project?.lastPathComponent,
         result.date.formatted(.relative(presentation: .named)),
         result.otherMatches > 0 ? String(localized: "+\(result.otherMatches) altri messaggi") : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// What VoiceOver reads: fonte, title, Progetto, who wrote the message, the message, when, the other matches.
    private var spokenLabel: String {
        var parts = [result.source == .session ? String(localized: "Sessione") : String(localized: "Cronologia CLI"), result.title,
                     result.project?.lastPathComponent ?? String(localized: "Progetto sconosciuto")]
        if let best = result.best {
            let excerpt = MatchHighlight.excerpt(of: best.text, matching: words)
            parts.append(best.message?.isFromUser == true ? String(localized: "Hai scritto: \(excerpt)")
                                                           : String(localized: "Claude ha scritto: \(excerpt)"))
        }
        parts.append(result.date.formatted(.relative(presentation: .named)))
        if result.otherMatches > 0 { parts.append(String(localized: "Altri \(result.otherMatches) messaggi trovati")) }
        return parts.joined(separator: ", ")
    }
}
