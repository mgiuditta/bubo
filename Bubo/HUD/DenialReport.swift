import SwiftUI

/// The report of an Esecuzione: the actions denied in its turn, and whether the Modalità autonoma was unavailable.
struct DenialReport: View {
    /// The denials, oldest first.
    let denials: [Denial]
    /// Whether the Modalità autonoma was asked for but `claude` ran in another mode: only the rules decided.
    let isAutonomyUnavailable: Bool
    /// The Regole of the Automazione now; `nil` when it is gone, and nothing can be allowed.
    let rules: [String]?
    /// Adds the rules of a denial to the Automazione.
    let allow: (Denial) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            if isAutonomyUnavailable {
                Label("Modalità autonoma non disponibile per questo modello o account: hanno deciso solo le Regole.",
                      systemImage: "info.circle")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !denials.isEmpty {
                Text("Azioni negate · \(denials.count)")
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(denials) { denial in
                    DenialRow(denial: denial,
                              isAllowed: rules.map { rules in denial.suggestions.allSatisfy(rules.contains) } ?? false,
                              allow: rules == nil ? nil : { allow(denial) })
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
