import SwiftUI

/// The Palette: one box, the gettoni of its filters, the commands, the conversations grouped by age and the notes of the
/// Secondo cervello on the left, and the preview of the chosen one on the right; ↑↓ choose, ↩ opens or runs, ⌥↩
/// resumes, ⌘↩ continues from the message found, esc closes.
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
                preview
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
        .task(id: model.selectedConversation) { await model.loadPreview() }
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
                      prompt: Text("Cerca comandi, conversazioni e note. Filtra con @progetto, 7g, cli"))
                .textFieldStyle(.plain)
                .font(Typography.body(size: 16))
                .focused($isFieldFocused)
                .onChange(of: model.query.text) { model.query.absorbFilters() }
                .onSubmit { model.openSelection() }
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.option) { return model.resumeSelection() ? .handled : .ignored }
                    if press.modifiers.contains(.command) { return model.continueFromSelection() ? .handled : .ignored }
                    return .ignored
                }
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
                    ForEach(model.sections) { section in
                        Text(section.title)
                            .font(Typography.mono(size: 10, weight: .medium))
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Spacing.small)
                            .padding(.top, Spacing.xSmall)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.items) { item in
                            row(for: item, isSelected: item.id == model.selected?.id)
                                .id(item.id)
                                .onTapGesture(count: 2) { model.activate(item) }
                                .onTapGesture { model.selection = item.id }
                                .accessibilityAction { model.activate(item) }
                        }
                    }
                    if model.sections.isEmpty {
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

    @ViewBuilder
    private func row(for item: PaletteItem, isSelected: Bool) -> some View {
        switch item {
        case .command(let command):
            PaletteCommandRow(command: command, words: model.searchedWords, isSelected: isSelected)
        case .conversation(let result):
            PaletteResultRow(result: result, words: model.searchedWords, isSelected: isSelected)
        case .note(let note):
            PaletteNoteRow(note: note, words: model.searchedWords, isSelected: isSelected)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch model.selected {
        case .note(let note):
            PalettePreview(title: note.title, messages: [note.best], found: note.best, words: model.searchedWords)
        case .command(let command):
            PalettePreview(title: command.title, messages: [], found: nil, words: [],
                           detail: command.shortcut.map { String(localized: "Scorciatoia: \($0)") })
        case .conversation(let result):
            PalettePreview(title: result.title, messages: model.preview, found: result.best, words: model.searchedWords,
                           detail: result.best == nil ? String(localized: "Scrivi per cercare nei messaggi.") : nil)
        case nil:
            PalettePreview(title: nil, messages: [], found: nil, words: [])
        }
    }

    private var emptyState: some View {
        Group {
            if model.hasFailed {
                Text("Ricerca non riuscita. Riprova tra poco.")
            } else if model.query.isEmpty {
                Text("Nessuna conversazione, per ora.")
            } else {
                Text("Nessun risultato. Prova altre parole o togli un filtro.")
            }
        }
        .font(Typography.body(size: 13))
        .foregroundStyle(Palette.textSecondary)
        .padding(Spacing.medium)
    }

    private var footer: some View {
        HStack(spacing: Spacing.medium) {
            Text("↑↓ scegli")
            Text("↩ apri o esegui")
            Text("⌥↩ riprendi")
            Text("⌘↩ continua da qui")
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
