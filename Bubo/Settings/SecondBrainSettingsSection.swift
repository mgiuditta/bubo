import SwiftUI

/// The choice of the Secondo cervello: any folder of notes, with the Obsidian vaults on this Mac suggested (spec 12).
struct SecondBrainSettingsSection: View {
    @Environment(SecondBrain.self) private var secondBrain
    @State private var isReachable = true
    @State private var isObsidianVault = false
    @State private var vaultCount = 0
    @State private var isSettingUp = false
    @State private var isSettingUpQuickly = false
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
                    Button("Personalizza a fondo…") { isSettingUp = true }
                    Button("Non usare più") { secondBrain.stopUsing() }
                }
            } else {
                LabeledContent {
                    HStack {
                        Button("Configura in 60 secondi…") { isSettingUpQuickly = true }
                        Button("Personalizza a fondo…") { isSettingUp = true }
                    }
                } label: {
                    Text("Nessuna cartella scelta")
                    if vaultCount == 0 {
                        Text("In 60 secondi scegli la cartella. A fondo, il modello ti intervista e prepara Profilo e Regole.")
                    } else {
                        Text("Vault di Obsidian trovati: \(vaultCount). In 60 secondi scegli la cartella. A fondo, il modello ti intervista e prepara Profilo e Regole.")
                    }
                }
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
        .sheet(isPresented: $isSettingUp) { SecondBrainConversationSheet() }
        .sheet(isPresented: $isSettingUpQuickly) { SecondBrainSetupSheet() }
        .task(id: secondBrain.location) { refresh() }
    }

    /// Reads whether the folder can be reached and is a vault, or which vaults to suggest.
    private func refresh() {
        isReachable = secondBrain.location?.isReachable ?? true
        isObsidianVault = secondBrain.location?.isObsidianVault ?? false
        vaultCount = secondBrain.location == nil ? SecondBrainLocation.suggestedVaults().count : 0
    }
}
