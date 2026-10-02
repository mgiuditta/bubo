import SwiftUI

/// One message of the Conversazione ripulita: who wrote it, then its text with the parts Bubo took out and the
/// possible secrets marked by a colour and by the text itself (`‹tolto›`, `‹abcd…›`), never by colour alone.
struct DeliveryPreviewLineView: View {
    let line: DeliveryPreviewLine
    let findings: [SecretScanner.Finding.ID: SecretScanner.Finding]
    let decisions: (SecretScanner.Finding.ID) -> DeliveryChoices.Decision?
    /// Whether "Mostra nella conversazione" brought the user here.
    let isShown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(line.isFromUser ? "Utente" : "Agente")
                .font(Typography.mono(size: 10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            Text(text)
                .font(Typography.body(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.xSmall)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .fill(isShown ? Palette.attention.opacity(0.12) : Palette.surface)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: AttributedString {
        var text = AttributedString()
        for segment in line.segments {
            switch segment {
            case let .plain(plain):
                text += AttributedString(plain)
            case let .removed(placeholder):
                var part = AttributedString(placeholder)
                part.foregroundColor = Palette.success
                text += part
            case let .secret(id):
                let removed = decisions(id) == .remove
                let masked = findings[id].map { "‹\($0.maskedExcerpt)›" } ?? "‹…›"
                var part = AttributedString(removed ? TranscriptCleaner.secretPlaceholder : masked)
                part.foregroundColor = removed ? Palette.success : Palette.ink
                if !removed { part.backgroundColor = Palette.attention }
                text += part
            }
        }
        return text
    }
}
