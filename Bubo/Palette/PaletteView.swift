import SwiftUI

/// The Palette: one box, the gettoni of its filters, the conversations grouped by age on the left and the preview of the
/// chosen one on the right; ↑↓ choose, ↩ opens, esc closes.
struct PaletteView: View {
    @Bindable var model: PaletteModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider().overlay(Palette.line)
            HStack(spacing: 0) {
                results
                    .frame(width: 440)
                Divider().overlay(Palette.line)
                PalettePreview(result: model.selected, messages: model.preview, words: model.searchedWords)
            }
            Divider().overlay(Palette.line)
            footer
        }
        .frame(width: PaletteWindow.size.width, height: PaletteWindow.size.height)
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.ink.opacity(0.92))
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        .clipShape(.rect(cornerRadius: CornerRadius.panel))
        .onAppear { isFieldFocused = true }
        .onExitCommand { model.close() }
        .task(id: model.query) { await model.refresh() }
        .task(id: model.selected) { await model.loadPreview() }
    }

    private var field: some View {
        HStack(spacing: Spacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            ForEach(model.query.filters, id: \.self) { filter in
                PaletteFilterChip(filter: filter) { model.query.remove(filter) }
            }
            TextField("Cerca", text: $model.query.text,
                      prompt: Text("Cerca nelle conversazioni o filtra: @progetto, 7g, cli"))
                .textFieldStyle(.plain)
                .font(Typography.body(size: 16))
                .focused($isFieldFocused)
                .onChange(of: model.query.text) { model.query.absorbFilters() }
                .onSubmit { model.openSelection() }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard model.query.text.isEmpty, !model.query.filters.isEmpty else { return .ignored }
                    model.query.removeLastFilter()
                    return .handled
                }
        }
        .padding(Spacing.medium)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    ForEach(model.groups) { group in
                        Text(group.age.title)
                            .font(Typography.mono(size: 10, weight: .medium))
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Spacing.small)
                            .padding(.top, Spacing.xSmall)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.results) { result in
                            PaletteResultRow(result: result, words: model.searchedWords,
                                             isSelected: result.id == model.selected?.id)
                                .id(result.id)
                                .onTapGesture(count: 2) { model.open(result) }
                                .onTapGesture { model.selection = result.id }
                                .accessibilityAction { model.open(result) }
                        }
                    }
                    if model.groups.isEmpty {
                        emptyState
                    }
                }
                .padding(Spacing.xSmall)
            }
            // Riduci movimento or not, the chosen row only jumps into view: no animated scrolling.
            .onChange(of: model.selection) { _, selection in
                if let selection { proxy.scrollTo(selection) }
            }
        }
    }

    private var emptyState: some View {
        Group {
            if model.hasFailed {
                Text("Ricerca non riuscita. Riprova tra poco.")
            } else if model.query.isEmpty {
                Text("Nessuna conversazione, per ora.")
            } else {
                Text("Nessuna conversazione trovata. Prova altre parole o togli un filtro.")
            }
        }
        .font(Typography.body(size: 13))
        .foregroundStyle(Palette.textSecondary)
        .padding(Spacing.medium)
    }

    private var footer: some View {
        HStack(spacing: Spacing.medium) {
            Text("↑↓ scegli")
            Text("↩ apri")
            Text("esc chiudi")
            Spacer()
            // Until the embedding model exists (#112) the Indice matches words only, and the Palette says so.
            Text("Per ora trova le parole, non il significato.")
        }
        .font(Typography.mono(size: 10, weight: .medium))
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xSmall)
    }
}
