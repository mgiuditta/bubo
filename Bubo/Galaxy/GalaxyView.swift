import SwiftUI

/// A Progetto's Galassia: the map with its names, and on the right the list with the search (spec 11).
struct GalaxyView: View {
    let model: GalaxyModel
    let store: GalaxyStore

    var body: some View {
        HSplitView {
            map
                .frame(minWidth: 360)
            GalaxyFileList(model: model) { index in
                guard let path = model.layout?.stars[index].path else { return }
                store.open(path, in: model.project)
            }
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 480)
        }
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.ink)
        .task {
            await model.load()
            await model.watch()
        }
    }

    private var map: some View {
        ZStack(alignment: .topLeading) {
            GalaxyMap(model: model)
                .accessibilityHidden(true)
            GalaxyLabels(model: model)
            state
            bar
        }
    }

    @ViewBuilder private var state: some View {
        if model.layout == nil {
            LoadingLabel("Leggo i file del Progetto…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.layout?.stars.isEmpty == true, !model.isListing {
            ContentUnavailableView("Nessun file in questo Progetto", systemImage: "sparkles")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bar: some View {
        HStack(spacing: Spacing.xSmall) {
            Menu {
                ForEach(store.projects(), id: \.self) { project in
                    Button(project.lastPathComponent) { store.show(project) }
                }
                Divider()
                Button("Scegli una cartella…") { store.chooseFolder() }
            } label: {
                Label(model.project.lastPathComponent, systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Apre la Galassia di un altro Progetto")
            Spacer(minLength: Spacing.xSmall)
            Button("Mostra tutto", systemImage: "arrow.up.left.and.arrow.down.right") { model.fit() }
                .keyboardShortcut("0")
                .disabled(model.layout == nil)
                .help("Mostra l'intera Galassia (⌘0)")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.small)
        // Room for the window's buttons: the bar sits under its transparent title bar.
        .padding(.top, 28)
    }
}
