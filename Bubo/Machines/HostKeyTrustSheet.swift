import SwiftUI

/// The first connection to a host: the fingerprint of the key it presented and how to check it on the host.
///
/// "Mi fido, connetti" answers OpenSSH `yes`, and OpenSSH writes the key in `~/.ssh/known_hosts`: Bubo keeps no
/// list of its own.
struct HostKeyTrustSheet: View {
    let store: MachineStore
    let machine: Machine
    let key: HostKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                Section {
                    LabeledContent("Impronta") {
                        Text(verbatim: "\(key.type) \(key.fingerprint)")
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Per verificarla, sull'host") {
                        Text(verbatim: HostKeyGate.verificationCommand(for: key))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Prima connessione a \(machine.address)")
                } footer: {
                    Text("Se l'impronta coincide, la chiave va in ~/.ssh/known_hosts, come con ssh dal Terminale.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { store.answer(nil) }
                    .keyboardShortcut(.cancelAction)
                // No default shortcut: Return must never trust a host by accident.
                Button("Mi fido, connetti") { store.answer("yes") }
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }
}

#Preview {
    HostKeyTrustSheet(store: MachineStore(file: nil), machine: Machine(alias: "nas", user: "ada", hostname: "nas.lan"),
                      key: HostKey(type: "ED25519", fingerprint: "SHA256:YN7R0X2SEUWLztTqXjJvEP8PClPWEsV7aTIP9uaQ8yc"))
}
