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
    /// A code of ``MeetingLanguage/offered``, or empty for the Mac's language.
    @AppStorage(MeetingLanguage.defaultsKey) private var meetingLanguage = ""
    @State private var isConfirmingStop = false

    var body: some View {
        @Bindable var secondBrain = secondBrain
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
                    Button("Non usare più…") { isConfirmingStop = true }
                        .confirmationDialog("Non usare più «\(location.name)»?", isPresented: $isConfirmingStop) {
                            Button("Non usare più", role: .destructive) { secondBrain.stopUsing() }
                        } message: {
                            Text("Le note restano nella cartella. Bubo dimentica le cartelle escluse e prioritarie.")
                        }
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
                        Text("Scegli la cartella delle note. Profilo e Regole puoi prepararli dopo, con «Personalizza a fondo».")
                    } else {
                        Text("Vault di Obsidian trovati: \(vaultCount). Scegli la cartella delle note. Profilo e Regole puoi prepararli dopo, con «Personalizza a fondo».")
                    }
                }
            }
            Toggle(isOn: $secondBrain.savesOnItsOwn) {
                Text("Salva da solo")
                Text("Bubo salva preferenze, persone, progetti e decisioni seguendo Bubo/Regole.md. Spento, salva solo quando glielo chiedi.")
            }
            if secondBrain.location != nil, !secondBrain.recentChanges.isEmpty {
                DisclosureGroup("Ultime modifiche") {
                    ForEach(secondBrain.recentChanges.prefix(10)) { change in
                        BrainChangeRow(change: change)
                    }
                }
            }
            Toggle("Scrivi un riassunto quando una Sessione è Fusa o Archiviata", isOn: $writesSummaries)
            Picker("Audio delle Riunioni", selection: $meetingAudio) {
                Text("Conserva per 30 giorni").tag(MeetingAudioRetention.thirtyDays)
                Text("Elimina dopo la trascrizione").tag(MeetingAudioRetention.afterTranscription)
            }
            // Always here: after the first Riunione the guided setup does not come back.
            Picker("Lingua delle Riunioni", selection: $meetingLanguage) {
                Text("La lingua del Mac").tag("")
                ForEach(MeetingLanguage.offered, id: \.self) { code in
                    Text(verbatim: Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code)
                        .tag(code)
                }
            }
            // The Mac's language is no value at all: an empty one would be read as a language with no name.
            .onChange(of: meetingLanguage) { _, code in
                if code.isEmpty { UserDefaults.standard.removeObject(forKey: MeetingLanguage.defaultsKey) }
            }
        } header: {
            Text("Secondo cervello")
        } footer: {
            Text("Ogni conversazione riceve Bubo/Profilo.md e Bubo/Regole.md; le altre note Claude le legge quando le cerca. Obsidian può restare chiuso.")
        }
        .sheet(isPresented: $isSettingUp) { SecondBrainConversationSheet() }
        // «60 secondi» is the folder only: the questions on the Riunioni come with the first Riunione, or below.
        .sheet(isPresented: $isSettingUpQuickly) { SecondBrainSetupSheet(steps: [.folder]) }
        .task(id: secondBrain.location) { refresh() }
    }

    /// Reads whether the folder can be reached and is a vault, or which vaults to suggest.
    private func refresh() {
        isReachable = secondBrain.location?.isReachable ?? true
        isObsidianVault = secondBrain.location?.isObsidianVault ?? false
        vaultCount = secondBrain.location == nil ? SecondBrainLocation.suggestedVaults().count : 0
    }
}
