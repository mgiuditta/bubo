import SwiftUI

/// A possible secret under Da decidere in the foglio di Consegna: rule, masked excerpt, where it is, and Togli ·
/// Lascia · Mostra nella conversazione, with no choice made beforehand. For VoiceOver one element with three actions.
struct SecretDecisionRow: View {
    let finding: SecretScanner.Finding
    let decision: DeliveryChoices.Decision?
    /// Whether the secret is also in the uncommitted changes, which Togli does not reach.
    let isInBranch: Bool
    let decide: (DeliveryChoices.Decision) -> Void
    let show: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(verbatim: finding.ruleID)
                    .font(Typography.mono(size: 11, weight: .medium))
                Text(verbatim: finding.maskedExcerpt)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.attention)
                Text("\(finding.length) caratteri")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                if let decision {
                    Label(decision == .remove ? "Tolto" : "Lasciato",
                          systemImage: decision == .remove ? "minus.circle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(decision == .remove ? Palette.success : Palette.textSecondary)
                }
            }
            Text(place)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: Spacing.xSmall) {
                Button("Togli") { decide(.remove) }
                Button("Lascia") { decide(.keep) }
                Button("Mostra nella conversazione", action: show)
                    .disabled(!isInConversation)
            }
            .controlSize(.small)
        }
        .padding(Spacing.xSmall)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .strokeBorder(decision == nil ? Palette.attention : Palette.line)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Possibile segreto \(finding.ruleID), inizia con \(finding.maskedExcerpt), \(finding.length) caratteri"))
        .accessibilityValue(decisionText)
        .accessibilityHint(Text(place))
        .accessibilityAction(named: Text("Togli")) { decide(.remove) }
        .accessibilityAction(named: Text("Lascia")) { decide(.keep) }
        .accessibilityAction(named: Text("Mostra nella conversazione"), show)
    }

    private var decisionText: Text {
        switch decision {
        case .remove: Text("Tolto")
        case .keep: Text("Lasciato")
        case nil: Text("Da decidere")
        }
    }

    private var isInConversation: Bool {
        finding.locations.contains { $0.file == SessionFiles.transcriptName && $0.lineID != nil }
    }

    /// Where the secret is: messages, subagent, tool results, uncommitted changes.
    private var place: String {
        let files = Set(finding.locations.map(\.file))
        var places: [String] = []
        if files.contains(SessionFiles.transcriptName) { places.append(String(localized: "nella conversazione")) }
        if files.contains(where: { $0.hasPrefix("agent-") }) { places.append(String(localized: "in un subagent")) }
        if files.contains(where: { !$0.hasPrefix("agent-") && $0 != SessionFiles.transcriptName
            && $0 != DeliveryManifest.bundleName }) {
            places.append(String(localized: "nei risultati degli strumenti"))
        }
        if isInBranch { places.append(String(localized: "nelle modifiche non salvate")) }
        return places.formatted(.list(type: .and))
    }
}
