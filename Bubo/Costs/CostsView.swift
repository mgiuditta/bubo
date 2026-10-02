import SwiftUI

/// The Costi window: the CostLedger's turns of a period, grouped in a table, with the chart of one unit over time and
/// the CSV of the table. Spesa, Valore a listino and Gratis stay apart everywhere (spec 18).
struct CostsView: View {
    let ledger: CostLedger
    /// The title of a Sessione still in Bubo.
    let sessionTitle: (UUID) -> String?
    /// Saves the CSV of the table, asking where.
    let export: (String) -> Void

    @State private var grouping = CostHistory.Grouping.project
    @State private var period = CostHistory.Period.month
    /// The unit the chart shows: one at a time, so its bars never mix two.
    @State private var chartUnit = CostUnit.spesa

    var body: some View {
        let history = CostHistory(entries: ledger.entries, grouping: grouping, period: period,
                                  sessionTitle: sessionTitle)
        VStack(alignment: .leading, spacing: Spacing.medium) {
            filters(history)
            CostTotals(history: history)
            chart(history)
            CostTable(history: history, grouping: grouping)
            notes
        }
        .padding(Spacing.large)
        .frame(minWidth: 860, minHeight: 600)
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.ink)
    }

    private func filters(_ history: CostHistory) -> some View {
        HStack(spacing: Spacing.medium) {
            Picker("Periodo", selection: $period) {
                ForEach(CostHistory.Period.allCases) { Text($0.title) }
            }
            .fixedSize()
            Picker("Raggruppa per", selection: $grouping) {
                ForEach(CostHistory.Grouping.allCases) { Text($0.title) }
            }
            .fixedSize()
            Spacer()
            Button("Esporta CSV…") { export(history.csv) }
                .disabled(history.rows.isEmpty)
        }
    }

    @ViewBuilder
    private func chart(_ history: CostHistory) -> some View {
        let units = CostUnit.charted.filter { history.points[$0] != nil }
        if !units.isEmpty {
            let unit = units.contains(chartUnit) ? chartUnit : units[0]
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if units.count > 1 {
                    Picker("Grafico", selection: $chartUnit) {
                        ForEach(units, id: \.self) { Text($0.title) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                CostChart(points: history.points[unit] ?? [], unit: unit, bucket: history.bucket)
                    .frame(height: 160)
            }
        }
    }

    /// What the window does not count, said rather than guessed (spec 18, Fonti dello storico).
    private var notes: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Contano i turni passati da Bubo. Gli altri strumenti a riga di comando, come Codex e Gemini CLI, sono fuori.")
            Text("La Quota dell'abbonamento è una percentuale, nell'HUD: non si somma a queste cifre.")
            Text("I crediti extra dell'abbonamento non compaiono: Bubo non li distingue ancora dagli altri consumi.")
        }
        .font(Typography.body(size: 12))
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension CostUnit {
    /// The units the chart shows, in dollars; Gratis has only tokens.
    static let charted: [CostUnit] = [.spesa, .valoreListino]

    /// The unit's name, as the glossary has it.
    var title: LocalizedStringResource {
        switch self {
        case .spesa: "Spesa"
        case .valoreListino: "Valore a listino"
        case .gratis: "Gratis"
        }
    }
}

extension CostHistory.Grouping {
    var title: LocalizedStringResource {
        switch self {
        case .project: "Progetto"
        case .session: "Sessione"
        case .model: "Modello"
        case .provider: "Fornitore"
        case .period: "Periodo"
        }
    }
}

extension CostHistory.Period {
    var title: LocalizedStringResource {
        switch self {
        case .week: "Ultimi 7 giorni"
        case .month: "Ultimi 30 giorni"
        case .quarter: "Ultimi 90 giorni"
        case .year: "Ultimi 12 mesi"
        case .all: "Tutto"
        }
    }
}

#Preview {
    let ledger = CostLedger()
    let usage = TurnUsage(mode: .apiKey, cost: 0.42, basis: .list, isComplete: true, models: [
        .init(model: "claude-sonnet-4-5", inputTokens: 1_200, outputTokens: 300, cacheReadTokens: 8_000,
              cacheWriteTokens: 400, thinkingTokens: 0, cost: 0.42),
    ])
    ledger.record(usage, turn: "t1", session: UUID(), project: URL(filePath: "/tmp/bubo"))
    return CostsView(ledger: ledger, sessionTitle: { _ in nil }, export: { _ in })
}
