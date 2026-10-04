import SwiftUI

/// A passphrase or a password OpenSSH asks, without `ssh-agent`: it goes to OpenSSH through a pipe and Bubo keeps
/// nothing of it.
struct PassphraseSheet: View {
    let store: MachineStore
    let machine: Machine
    /// OpenSSH's own question, such as "Enter passphrase for key '~/.ssh/id_ed25519':".
    let prompt: String
    @State private var secret = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                Section {
                    SecureField(text: $secret) {
                        Text(verbatim: prompt)
                    }
                    .focused($isFocused)
                } header: {
                    Text("Connessione a \(machine.address)")
                } footer: {
                    Text("Va solo a ssh: Bubo non la conserva.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { store.answer(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Continua") { store.answer(secret) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(secret.isEmpty)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 460)
        .interactiveDismissDisabled()
        .onAppear { isFocused = true }
    }
}

#Preview {
    PassphraseSheet(store: MachineStore(file: nil), machine: Machine(alias: "nas", user: "ada", hostname: "nas.lan"),
                    prompt: "Enter passphrase for key '/Users/ada/.ssh/id_ed25519':")
}
