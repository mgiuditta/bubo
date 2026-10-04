import SwiftUI
import UniformTypeIdentifiers

/// The folders of the Secondo cervello the Indice leaves out, and the warning when it grows too large (spec).
struct ExcludedFoldersSection: View {
    @Environment(SecondBrain.self) private var secondBrain
    @State private var isChoosingFolder = false
    @State private var isOutside = false

    var body: some View {
        if let location = secondBrain.location {
            Section {
                if let load = secondBrain.fragmentLoad, load.exceedsLimit {
                    Label("L'Indice ha \(load.fragmentCount.formatted(.number)) frammenti, oltre i \(load.limit.formatted(.number)) previsti: le ricerche rallentano. Escludi le cartelle che non ti servono.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.textSecondary)
                        .font(.callout)
                    ForEach(load.largestFolders, id: \.relativePath) { folder in
                        LabeledContent {
                            Button("Escludi") { exclude(location.url.appending(path: folder.relativePath)) }
                                .accessibilityLabel("Escludi \(folder.relativePath)")
                        } label: {
                            Text(verbatim: folder.relativePath)
                            Text("\(folder.fragmentCount) frammenti")
                        }
                    }
                }
                if location.excludedFolders.isEmpty {
                    Text("Nessuna cartella esclusa.")
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(location.excludedFolders, id: \.self) { folder in
                    LabeledContent {
                        Button("Includi") { secondBrain.include(folder) }
                            .accessibilityLabel("Includi \(folder)")
                    } label: {
                        Text(verbatim: folder)
                    }
                }
                Button("Escludi una cartella…") { isChoosingFolder = true }
                if isOutside {
                    Text("Scegli una cartella dentro il Secondo cervello.")
                        .font(.callout)
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                Text("Cartelle escluse")
            } footer: {
                Text("L'Indice non legge queste cartelle. Le note restano dove sono.")
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                guard case let .success(folder) = result else { return }
                exclude(folder)
            }
            .fileDialogDefaultDirectory(location.url)
            .task(id: location.excludedFolders) {
                await secondBrain.refreshFragmentLoad()
                // The Indice applies the change in the background: read again once it had time to.
                try? await Task.sleep(for: .seconds(2))
                await secondBrain.refreshFragmentLoad()
            }
        }
    }

    private func exclude(_ folder: URL) {
        do {
            try secondBrain.exclude(folder)
            isOutside = false
        } catch {
            isOutside = true
        }
    }
}
