import SwiftUI

/// The Cronologia window: the filters with their counts, the results of the search, and the conversation read only.
struct HistoryView: View {
    @Bindable var model: HistoryModel

    var body: some View {
        HStack(spacing: 0) {
            HistoryFilterColumn(model: model)
                .frame(width: 200)
            Divider().overlay(Palette.line)
            results
                .frame(width: 360)
            Divider().overlay(Palette.line)
            if let reader = model.reader {
                ConversationReaderView(reader: reader)
            } else {
                Text("Scegli una conversazione per leggerla.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 480)
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.ink)
        .task(id: model.text) { await model.refresh() }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                TextField("Cerca", text: $model.text, prompt: Text("Cerca nelle conversazioni"))
                    .textFieldStyle(.plain)
                    .font(Typography.body(size: 14))
                    .onKeyPress(.upArrow) {
                        model.moveSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveSelection(by: 1)
                        return .handled
                    }
            }
            .padding(Spacing.small)
            Divider().overlay(Palette.line)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    let groups = model.visibleGroups()
                    ForEach(groups) { group in
                        Text(group.age.title)
                            .font(Typography.mono(size: 10, weight: .medium))
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Spacing.small)
                            .padding(.top, Spacing.xSmall)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.results) { result in
                            PaletteResultRow(result: result, words: MatchHighlight.words(of: model.text),
                                             isSelected: result.id == model.reader?.result.id)
                                .onTapGesture { model.read(result) }
                                .accessibilityAction { model.read(result) }
                        }
                    }
                    if groups.isEmpty {
                        Text(model.hasFailed ? "Ricerca non riuscita. Riprova tra poco."
                                             : "Nessuna conversazione trovata. Prova altre parole o togli un filtro.")
                            .font(Typography.body(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(Spacing.medium)
                    }
                }
                .padding(Spacing.xSmall)
            }
        }
    }
}
