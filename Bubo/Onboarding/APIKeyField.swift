import SwiftUI

/// The field where the user gives `claude` an API key instead of its login (ADR 0003), in the remedy under the Orb and
/// in the Claude card of the step of the Motore: saved in the keychain, then `claude` answers with it.
///
/// Offers the key already saved when there is one Bubo has not tried yet. Never shows the key once saved.
struct APIKeyField: View {
    let flow: OnboardingFlow
    /// Whether the field is open; closed once the key is saved.
    @Binding var isEntering: Bool
    @State private var key = ""
    /// Whether a key is already in the keychain; `nil` until read.
    @State private var hasSavedKey: Bool?
    /// Why saving failed, if it did. Never contains the key.
    @State private var failure: String?

    var body: some View {
        if isEntering {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: Spacing.small) {
                    SecureField("API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                        .accessibilityLabel("API key")
                    Button("Salva", action: saveKey)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    // A refused key is the one Bubo used: offering it again would not help.
                    if hasSavedKey == true && !flow.usesAPIKey {
                        Button("Usa quella salvata") { Task { await flow.useAPIKey() } }
                    }
                }
                if !flow.usesAPIKey || flow.problem != nil {
                    Text("La chiave resta nel Portachiavi di questo Mac e si paga a consumo.")
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                if let failure {
                    Text(failure)
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.danger)
                }
            }
            .task { hasSavedKey = try? await APIKeyStore().containsKey() }
        }
    }

    /// Saves the key in the keychain and answers with it from now on.
    private func saveKey() {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task {
            do {
                try await APIKeyStore().save(key)
                self.key = ""
                failure = nil
                isEntering = false
                await flow.useAPIKey()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
