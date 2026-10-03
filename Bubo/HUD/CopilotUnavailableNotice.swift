import SwiftUI

/// What a Sessione on Copilot does without: each part that exists only with Claude, with why (ADR 0012).
struct CopilotUnavailableNotice: View {
    var features: [ClaudeOnlyFeature] = ClaudeOnlyFeature.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Non disponibile con Copilot")
                .font(Typography.mono(size: 10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(features) { feature in
                VStack(alignment: .leading, spacing: 0) {
                    Text(feature.title)
                        .font(Typography.body(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(feature.explanation)
                        .font(Typography.body(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    CopilotUnavailableNotice()
        .padding()
        .frame(width: 320)
        .background(Palette.ink)
}
