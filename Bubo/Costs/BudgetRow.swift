import SwiftUI

/// One Budget in Impostazioni › Budget: on or off, its monthly limit and what is spent of it this month.
struct BudgetRow: View {
    let scope: BudgetGuard.Scope
    let settings: BudgetSettings
    /// This month's state; `nil` while the Budget is off.
    let status: BudgetGuard.Status?
    /// Where the provider sets its own hard limit; `nil` for a Progetto, the total and an unknown provider.
    var providerLimits: URL?

    var body: some View {
        Toggle(scope.name, isOn: isOn)
        if let status {
            TextField("Limite mensile", value: limit, format: .currency(code: "USD"))
            Text(spentLine(of: status))
                .font(.callout)
                .foregroundStyle(status.level == .below ? Color.secondary : Palette.attention)
            if status.spent.isUncertain {
                Text("Cifra incerta: un turno di Claude su un modello senza prezzo noto è stimato alla tariffa del modello predefinito.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if status.unpricedTurns > 0 {
                Text("Turni senza prezzo questo mese, che il Budget non può contare: \(status.unpricedTurns)")
                    .font(.callout)
                    .foregroundStyle(Palette.attention)
            }
        }
        if let providerLimits {
            Link("Limite duro su \(scope.name)", destination: providerLimits)
                .font(.callout)
        }
    }

    private func spentLine(of status: BudgetGuard.Status) -> String {
        String(localized: "Spesi \(SessionCostTotal.formatted(status.spent.value)) su \(status.limit.formatted(.currency(code: "USD"))) questo mese, restano \(status.remaining.formatted(.currency(code: "USD"))).",
               comment: "A Budget this month: the Spesa, the monthly limit and what is left.")
    }

    private var isOn: Binding<Bool> {
        Binding {
            settings.budgets.limit(of: scope) != nil
        } set: { isOn in
            settings.budgets.setLimit(isOn ? Self.firstLimit : nil, of: scope)
        }
    }

    private var limit: Binding<Decimal> {
        Binding {
            settings.budgets.limit(of: scope) ?? Self.firstLimit
        } set: { limit in
            settings.budgets.setLimit(max(limit, 0), of: scope)
        }
    }

    /// The limit a Budget starts at when the user turns it on.
    private static let firstLimit: Decimal = 20
}
