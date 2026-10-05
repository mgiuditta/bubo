import SwiftUI

/// The Spesa of Copilot this month at the top of the HUD, in place of the Quota when Bubo has no `claude` (#729).
///
/// An estimate from the tokens on GitHub's list prices: Bubo does not see the credits taken from the account. A click
/// opens the Costi window, as the Quota's.
struct CopilotSpendView: View {
    let spent: CostLedger.Amount
    /// Opens the Costi window.
    var showCosts: () -> Void = {}

    var body: some View {
        Button(action: showCosts) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: Spacing.xSmall) {
                    Text("Spesa Copilot")
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.textSecondary)
                    Text(verbatim: SessionCostTotal.phrase(spent))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.isReduced ? nil : Motion.standard, value: spent.value)
                }
                .font(Typography.mono(size: 11, weight: .medium))
                Text("stimata, questo mese")
                    .font(Typography.mono(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .help("Apri i Costi")
        .accessibilityHint(Text("Apre la finestra Costi"))
    }
}

#Preview {
    CopilotSpendView(spent: CostLedger.Amount(value: 1.27))
        .padding()
        .background(Palette.ink)
}
