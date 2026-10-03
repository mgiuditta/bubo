import SwiftUI
import UniformTypeIdentifiers

/// The choice of the Secondo cervello: any folder of notes, with the Obsidian vaults on this Mac suggested (spec 12).
struct SecondBrainSettingsSection: View {
    @Environment(SecondBrain.self) private var secondBrain
    @State private var isReachable = true
    @State private var isObsidianVault = false
    @State private var vaults: [URL] = []
    @State private var isChoosingFolder = false
    @AppStorage(SessionSummarizer.defaultsKey) private var writesSummaries = true
    @AppStorage(MeetingAudioRetention.defaultsKey) private var meetingAudio = MeetingAudioRetention.thirtyDays

    var body: some View {
        Section {
            if let location = secondBrain.location {
                LabeledContent {
                    Text(verbatim: location.name)
                        .help(location.path)
                } label: {
                    Text("Cartella")
                    if isObsidianVault {
                        Text("Vault di Obsidian")
                    }
                }
                if !isReachable {
                    Label("Non trovo la cartella: le ricerche usano l'ultima copia delle note.",
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
                HStack {
                    Button("Cambia cartella…") { isChoosingFolder = true }
                    Button("Non usare più") { secondBrain.stopUsing() }
                }
            } else {
                ForEach(vaults, id: \.self) { vault in
                    LabeledContent {
                        Button("Usa") { secondBrain.choose(vault) }
                            .accessibilityLabel("Usa \(vault.lastPathComponent)")
                    } label: {
                        Text(verbatim: vault.lastPathComponent)
                        Text("Vault di Obsidian")
                    }
                    .help(vault.path)
                }
                Button("Scegli una cartella…") { isChoosingFolder = true }
            }
            Toggle("Scrivi un riassunto quando una Sessione è Fusa o Archiviata", isOn: $writesSummaries)
            Picker("Audio delle Riunioni", selection: $meetingAudio) {
                Text("Conserva per 30 giorni").tag(MeetingAudioRetention.thirtyDays)
                Text("Elimina dopo la trascrizione").tag(MeetingAudioRetention.afterTranscription)
            }
        } header: {
            Text("Secondo cervello")
        } footer: {
            Text("Claude legge le note solo quando le cerca: nulla entra da solo nella conversazione. Obsidian può restare chiuso.")
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }
            secondBrain.choose(folder)
        }
        .task(id: secondBrain.location) { refresh() }
    }

    /// Reads whether the folder can be reached and is a vault, or which vaults to suggest.
    private func refresh() {
        isReachable = secondBrain.location?.isReachable ?? true
        isObsidianVault = secondBrain.location?.isObsidianVault ?? false
        vaults = secondBrain.location == nil ? SecondBrainLocation.suggestedVaults() : []
    }
}
