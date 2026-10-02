import SwiftUI

/// Impostazioni › Voce: OpenAI's voice for the Sintesi parlata, off by default and possible only with the OpenAI key.
struct VoiceSettingsView: View {
    @AppStorage(OpenAIVoice.isOnKey) private var speaksWithOpenAI = false
    /// Whether the OpenAI key is in the keychain; `nil` until read.
    @State private var hasKey: Bool?

    var body: some View {
        Form {
            Section {
                Toggle("Voce di OpenAI", isOn: hasKey == true ? $speaksWithOpenAI : .constant(false))
                    .tint(Palette.switchTrack)
                    .disabled(hasKey != true)
                Group {
                    if hasKey == false {
                        Text("Serve la chiave di OpenAI: aggiungila in Modelli.")
                    } else {
                        Text("Una voce più naturale per la Sintesi parlata. OpenAI riceve solo il testo della Sintesi, con la tua chiave, e il costo va sul tuo account. Se OpenAI non risponde, Bubo parla con le voci del Mac.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refreshKey() }
    }

    private func refreshKey() async {
        do {
            hasKey = try await APIKeyStore(account: OpenAIVoice.keychainAccount).containsKey()
        } catch {
            hasKey = false
        }
    }
}
