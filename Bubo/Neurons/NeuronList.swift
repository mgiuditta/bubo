import SwiftUI

/// The list next to the map: the folder filter, the search and the notes they leave, each with its folder and its
/// links.
///
/// It is the map's accessible equivalent: selecting a row flies the camera to its note and lights its links, a click on
/// a note selects its row, and a double click or Return opens the note.
struct NeuronList: View {
    @Bindable var model: NeuronModel
    /// Opens the note at an index.
    let open: (Int) -> Void
    @State private var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filters
                .padding(Spacing.small)
                // Room for the window's buttons over the list too.
                .padding(.top, 20)
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

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Picker("Cartella", selection: $model.folder) {
                Text("Tutte le cartelle").tag(String?.none)
                if let folders = model.graph?.folders, !folders.isEmpty {
                    Divider()
                    ForEach(folders, id: \.self) { folder in
                        if folder.isEmpty {
                            Text("Note fuori dalle cartelle").tag(String?.some(folder))
                        } else {
                            Text(verbatim: folder).tag(String?.some(folder))
                        }
                    }
                }
            }
            TextField("Cerca per nome o percorso", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .onExitCommand { model.query = "" }
            Text("\(model.rows.count) note")
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                if let graph = model.graph {
                    let folders = graph.folders
                    ForEach(model.rows, id: \.self) { index in
                        let note = graph.notes[index]
                        NeuronRow(note: note, color: NeuronRenderer.color(of: note.folder, among: folders),
                                  isCited: model.cited.contains(index))
                            .accessibilityAction(named: Text("Apri la nota")) { open(index) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: Int.self) { indices in
                if let index = indices.first {
                    Button("Apri la nota", systemImage: "doc.text") { open(index) }
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
