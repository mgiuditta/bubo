import SwiftUI

/// The total of each unit in the period, side by side and never added together: Spesa, Valore a listino, Gratis.
struct CostTotals: View {
    let history: CostHistory

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.large) {
            ForEach(CostUnit.allCases.filter { history.totals[$0] != nil }, id: \.self) { unit in
                total(of: unit)
            }
            if history.totals.isEmpty {
                Text("Nessun turno in questo periodo.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func total(of unit: CostUnit) -> some View {
        let amount = history.totals[unit] ?? CostLedger.Amount()
        let tokens = history.tokens[unit]?.total ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(unit.title)
                .font(Typography.mono(size: 11, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            if unit == .gratis {
                Text("\(tokens, format: .number) token")
                    .font(Typography.display(size: 22))
            } else {
                Text(amount.value, format: .currency(code: "USD"))
                    .font(Typography.display(size: 22))
                    .monospacedDigit()
                Text("\(tokens, format: .number) token")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            if amount.isIncomplete {
                Text("Manca la cifra di qualche turno")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
