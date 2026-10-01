import SwiftUI

/// The list next to the map: the search on names and paths and the Progetto's files, or the results.
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
                if model.query.isEmpty {
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
                        GalaxyFileRow(path: stars[index].path)
                            .accessibilityAction(named: Text("Apri nel Visore")) { open(index) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
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
