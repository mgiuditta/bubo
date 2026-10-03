import SwiftUI
import UniformTypeIdentifiers

/// The folders of the Secondo cervello whose notes `cerca` puts first, chosen in the guided setup or here (#554).
struct PriorityFoldersSection: View {
    @Environment(SecondBrain.self) private var secondBrain
    @State private var isChoosingFolder = false
    @State private var isOutside = false

    var body: some View {
        if let location = secondBrain.location {
            Section {
                if location.priorityFolders.isEmpty {
                    Text("Nessuna cartella prioritaria: cerco in tutte allo stesso modo.")
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(location.priorityFolders, id: \.self) { folder in
                    LabeledContent {
                        Button("Togli") {
                            secondBrain.prioritizeOnly(Set(location.priorityFolders).subtracting([folder]))
                        }
                        .accessibilityLabel("Togli \(folder)")
                    } label: {
                        Text(verbatim: folder)
                    }
                }
                Button("Aggiungi una cartella…") { isChoosingFolder = true }
                if isOutside {
                    Text("Scegli una cartella dentro il Secondo cervello.")
                        .font(.callout)
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                Text("Cartelle prioritarie")
            } footer: {
                Text("Quando la ricerca trova note in cartelle diverse, queste vengono prima.")
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                guard case let .success(folder) = result else { return }
                do {
                    try secondBrain.prioritize(folder)
                    isOutside = false
                } catch {
                    isOutside = true
                }
            }
            .fileDialogDefaultDirectory(location.url)
        }
    }
}
