import SwiftUI

/// The list next to the map: the chips of the Sessioni, the search on names and paths and the Progetto's files, the
/// results, or the files the filtered Sessione wrote with how many it read.
///
/// It is the map's accessible equivalent: selecting a row flies the camera to its star, a click on a star selects its
/// row, and a double click or Return opens the file in the Visore.
struct GalaxyFileList: View {
    @Bindable var model: GalaxyModel
    /// Opens the file at the star's index in the Visore.
    let open: (Int) -> Void
    @State private var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.sessions.isEmpty {
                GalaxySessionChips(model: model)
                    .padding([.horizontal, .top], Spacing.small)
            }
            search
                .padding(Spacing.small)
            Divider()
                .overlay(Palette.line)
            list
        }
        .onChange(of: model.selection) { _, selected in
            selection = selected
        }
        .onChange(of: selection) { _, selected in
            model.select(selected)
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            TextField("Cerca per nome o percorso", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .onExitCommand { model.query = "" }
            Group {
                if let filter = model.filter {
                    // Reads are many and faint: counted, not listed.
                    HStack(spacing: Spacing.xxSmall) {
                        Text("\(model.writtenStars(by: filter).count) file modificati")
                        Text(verbatim: "·")
                        Text("\(model.readCount(of: filter)) letture")
                    }
                    .accessibilityElement(children: .combine)
                } else if model.query.isEmpty {
                    Text("\(model.layout?.stars.count ?? 0) file")
                } else {
                    Text("\(model.matches.count) risultati")
                }
            }
            .font(Typography.mono(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                if let stars = model.layout?.stars {
                    ForEach(model.rows, id: \.self) { index in
                        GalaxyFileRow(path: stars[index].path, writers: model.sessionsWriting(index),
                                      lineCounts: model.lineCounts(of: index))
                            .accessibilityAction(named: Text("Apri nel Visore")) { open(index) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                // A search with no results says so, not that the Sessione changed nothing.
                if model.rows.isEmpty, !model.query.isEmpty {
                    ContentUnavailableView.search(text: model.query)
                } else if model.filter != nil, model.rows.isEmpty {
                    ContentUnavailableView("Nessun file modificato", systemImage: "doc")
                }
            }
            .contextMenu(forSelectionType: Int.self) { indices in
                if let index = indices.first {
                    Button("Apri nel Visore", systemImage: "doc.text") { open(index) }
                }
            } primaryAction: { indices in
                if let index = indices.first { open(index) }
            }
            .onChange(of: model.revealedInList) { _, index in
                guard let index else { return }
                proxy.scrollTo(index, anchor: .center)
                model.didRevealInList()
            }
        }
    }
}
