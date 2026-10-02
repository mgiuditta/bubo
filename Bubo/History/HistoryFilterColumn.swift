import SwiftUI

/// The left column of the Cronologia window: Progetto, date and fonte, each choice with how many results it leaves.
struct HistoryFilterColumn: View {
    @Bindable var model: HistoryModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                section("Progetto") {
                    choice(Text("Tutti"), isChosen: model.filters.project == nil) { $0.project = nil }
                    ForEach(model.projectNames, id: \.self) { name in
                        choice(Text(verbatim: name), isChosen: model.filters.project == name) { $0.project = name }
                    }
                }
                section("Data") {
                    ForEach(HistoryFilters.dayOptions, id: \.self) { days in
                        choice(title(ofDays: days), isChosen: model.filters.days == days) { $0.days = days }
                    }
                }
                section("Fonte") {
                    choice(Text("Tutte"), isChosen: model.filters.source == nil) { $0.source = nil }
                    choice(Text("Sessioni"), isChosen: model.filters.source == .session) { $0.source = .session }
                    choice(Text("Cronologia CLI"), isChosen: model.filters.source == .cli) { $0.source = .cli }
                }
            }
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filtri"))
    }

    private func title(ofDays days: Int?) -> Text {
        days.map { Text("Ultimi \($0) giorni") } ?? Text("Tutte")
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(title)
                .font(Typography.mono(size: 10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// One choice of a filter: its name, then how many results it leaves; the chosen one is marked.
    private func choice(_ title: Text, isChosen: Bool,
                        change: @escaping (inout HistoryFilters) -> Void) -> some View {
        let count = model.count(changing: change)
        return Button {
            change(&model.filters)
        } label: {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: "checkmark")
                    .opacity(isChosen ? 1 : 0)
                    .accessibilityHidden(true)
                title
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                Text(count, format: .number)
                    .font(Typography.mono(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .font(Typography.body(size: 13))
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(isChosen ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.small))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text("\(count) risultati"))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
