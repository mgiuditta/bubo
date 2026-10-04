import SwiftUI

/// The total of a Sessione in its header, 0 clicks away: the Spesa, and the Valore a listino in second place, each
/// on its own line, never added together. With the API key, also the Spesa of the latest turn.
struct SessionCostTotal: View {
    let total: [CostUnit: CostLedger.Amount]
    /// The latest turn of the Sessione.
    let lastTurn: TurnUsage?
    /// The day of the Copilot list prices, for a Sessione on Copilot: its Spesa is an estimate from its tokens;
    /// `nil` for a Sessione on Claude.
    var copilotPricesOf: Date?

    var body: some View {
        if !total.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                if let spesa = total[.spesa] {
                    if copilotPricesOf != nil {
                        Text("Spesa stimata \(Self.phrase(spesa))")
                            .foregroundStyle(Palette.textPrimary)
                    } else if let lastTurn, lastTurn.unit == .spesa, let cost = lastTurn.cost {
                        Text("Spesa \(Self.phrase(spesa)) · ultimo turno \(Self.formatted(cost))")
                            .foregroundStyle(Palette.textPrimary)
                    } else {
                        Text("Spesa \(Self.phrase(spesa))")
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                if let value = total[.valoreListino] {
                    Text("\(Self.phrase(value)) a listino, incluso nell'abbonamento")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.mono(size: 11))
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(Motion.isReduced ? nil : Motion.standard, value: total[.spesa]?.value)
            .animation(Motion.isReduced ? nil : Motion.standard, value: total[.valoreListino]?.value)
            .help(origin)
        }
    }

    /// Where the figures come from, and why one may be uncertain or incomplete.
    private var origin: String {
        var lines = if let copilotPricesOf {
            [String(localized: "Stima dai token sul listino GitHub Copilot del \(copilotPricesOf.formatted(date: .long, time: .omitted)), 1 credito = $0,01. Bubo non vede i crediti scalati dal tuo account.")]
        } else {
            [String(localized: "Stima a listino di Claude Code, calcolata sul Mac: non è una fattura.")]
        }
        if total.values.contains(where: \.isUncertain) {
            lines.append(String(localized: "«circa»: un modello senza prezzo noto è contato al prezzo del modello predefinito."))
        }
        if total.values.contains(where: \.isIncomplete) {
            lines.append(String(localized: "«almeno»: un turno si è interrotto, ne conto i token ma non tutta la cifra."))
        }
        return lines.joined(separator: "\n")
    }

    /// `amount` in dollars, said as uncertain or incomplete when it is.
    static func phrase(_ amount: CostLedger.Amount) -> String {
        let value = formatted(amount.value)
        if amount.isIncomplete { return String(localized: "almeno \(value)") }
        if amount.isUncertain { return String(localized: "circa \(value)") }
        return value
    }

    /// `value` in dollars to the cent; under a cent, but not zero, "meno di" a cent.
    static func formatted(_ value: Decimal) -> String {
        let cent = Decimal(sign: .plus, exponent: -2, significand: 1)
        guard value > 0, value < cent else { return value.formatted(.currency(code: "USD")) }
        return String(localized: "meno di \(cent.formatted(.currency(code: "USD")))")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.small) {
        SessionCostTotal(total: [.spesa: .init(value: 0.42)],
                         lastTurn: TurnUsage(mode: .apiKey, cost: 0.03, basis: .list, isComplete: true, models: []))
        SessionCostTotal(total: [.valoreListino: .init(value: 1.2, isUncertain: true)], lastTurn: nil)
        SessionCostTotal(total: [.spesa: .init(value: 0.004, isIncomplete: true), .valoreListino: .init(value: 3.5)],
                         lastTurn: nil)
        SessionCostTotal(total: [.spesa: .init(value: 0.37)], lastTurn: nil, copilotPricesOf: .now)
    }
    .padding()
    .background(Palette.ink)
}
