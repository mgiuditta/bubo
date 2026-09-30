import SwiftUI

/// Asks for an API key; the key is typed in a secure field and never shown.
struct APIKeySheet: View {
    /// Receives the trimmed key when the user saves.
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            SecureField("API key", text: $key, prompt: Text(verbatim: "sk-ant-…"))
            Text("La chiave resta nel Portachiavi di questo Mac e non va su iCloud. Bubo non la usa mai da solo: si paga a consumo.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    save(trimmedKey)
                    dismiss()
                }
                .disabled(trimmedKey.isEmpty)
            }
        }
    }
}
