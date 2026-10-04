import SwiftUI

/// The rows of the period: one per group, unit and origin, with Spesa, Valore a listino and the command line's
/// estimate in columns of their own.
struct CostTable: View {
    let history: CostHistory
    let grouping: CostHistory.Grouping

    var body: some View {
        Table(history.rows) {
            TableColumn(Text(grouping.title)) { row in
                if let date = row.date {
                    Text(date, format: history.bucket == .month ? .dateTime.month(.wide).year()
                                                                : .dateTime.day().month(.abbreviated).year())
                } else {
                    Text(row.group)
                }
            }
            TableColumn("Spesa") { row in figure(of: row, in: .spesa) }
                .width(min: 80, ideal: 100)
            TableColumn("Valore a listino") { row in figure(of: row, in: .valoreListino) }
                .width(min: 80, ideal: 110)
            TableColumn("Riga di comando") { row in figure(of: row, in: .rigaDiComando) }
                .width(min: 80, ideal: 110)
            TableColumn("Token") { row in
                Text(row.tokens.total, format: .number)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Turni") { row in
                Text(row.turns, format: .number)
                    .monospacedDigit()
            }
            .width(min: 40, ideal: 50)
            TableColumn("Origine") { row in Text(row.originDescription) }
                .width(min: 160, ideal: 240)
        }
        .scrollContentBackground(.hidden)
    }

    /// The row's figure in the column of `unit`; nothing in the other column, or for a model with no price.
    @ViewBuilder
    private func figure(of row: CostHistory.Row, in unit: CostUnit) -> some View {
        if row.unit == unit, row.origin != .unpriced {
            Text(row.amount.value, format: .currency(code: "USD"))
                .monospacedDigit()
        }
    }
}

extension CostHistory.Row {
    /// Where the row's figure comes from, with what makes it less than exact.
    var originDescription: String {
        let source = switch origin {
        case .reported: String(localized: "Riportata dal fornitore")
        case .listEstimate: String(localized: "Stima a listino")
        case .priceTable:
            priceDate.map { String(localized: "Prezzo da tabella del \($0.formatted(date: .abbreviated, time: .omitted))") }
                ?? String(localized: "Prezzo da tabella")
        case .unpriced: String(localized: "Senza prezzo")
        case .free: String(localized: "Gratis")
        }
        var parts = [source]
        if amount.isUncertain { parts.append(String(localized: "modello senza prezzo noto all'SDK")) }
        if amount.isIncomplete { parts.append(String(localized: "manca qualche cifra")) }
        return parts.joined(separator: " · ")
    }
}
