import SwiftUI

/// A sentence of the trascrizione in the Suggeritore: who said it in the data font, the user's own words brighter.
struct PromptLineView: View {
    let line: MeetingLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(verbatim: line.speaker?.label ?? "")
                .font(.buboData)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            Text(verbatim: line.text)
                .font(.buboInterface)
                .foregroundStyle(line.speaker == .me ? Palette.textPrimary : Palette.textSecondary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
