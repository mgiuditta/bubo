import SwiftUI

/// A note of the Secondo cervello in the Palette: the section that answers best, then the note's name and how many
/// other sections answer.
struct PaletteNoteRow: View {
    let note: NoteResult
    let words: [String]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HighlightedText(text: excerpt, words: words, isFoundByMeaning: note.best.isFoundByMeaningOnly)
                .font(Typography.body(size: 13))
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(verbatim: note.title)
                    .font(Typography.body(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                if note.otherMatches > 0 {
                    Text("+\(note.otherMatches) altri punti")
                        .font(Typography.mono(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .paletteRowStyle(isSelected: isSelected)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityHint(Text("Apre la nota"))
    }

    private var excerpt: String { MatchHighlight.excerpt(of: note.best.text, matching: words) }

    /// What VoiceOver reads: the Secondo cervello, the note, the section, the other matches.
    private var spokenLabel: String {
        var parts = [String(localized: "Secondo cervello"), note.title, excerpt]
        if note.best.isFoundByMeaningOnly { parts.append(String(localized: "Trovato per significato")) }
        if note.otherMatches > 0 { parts.append(String(localized: "Altri \(note.otherMatches) punti")) }
        return parts.joined(separator: ", ")
    }
}
