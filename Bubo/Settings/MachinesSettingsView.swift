import SwiftUI

/// Impostazioni › Macchine: the hosts of `~/.ssh/config`, their state and their first connection, and Rimuovi
/// Macchina.
struct MachinesSettingsView: View {
    @State private var store = MachineStore()
    /// The blocked Macchina whose details are shown.
    @State private var details: Machine?
    /// The Macchina waiting for the confirmation of Rimuovi Macchina.
    @State private var removing: Machine?

    var body: some View {
        Form {
            Section {
                if store.machines.isEmpty {
                    Text("Nessun host in ~/.ssh/config. Aggiungine uno, poi torna qui.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.machines) { machine in
                        row(for: machine)
                    }
                }
            } header: {
                Text("Da ~/.ssh/config")
            } footer: {
                Text("Bubo usa ssh e ~/.ssh/config del Mac e non conserva chiavi né password.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await store.refresh() }
        .sheet(item: questionBinding) { asked in
            switch asked.question {
            case .newHostKey(let key):
                HostKeyTrustSheet(store: store, machine: asked.machine, key: key)
            case .secret(let prompt):
                PassphraseSheet(store: store, machine: asked.machine, prompt: prompt)
            }
        }
        .sheet(item: $details) { machine in
            if let change = store.records[machine.alias]?.keyChange {
                HostKeyChangedSheet(machine: machine, change: change)
            }
        }
        .confirmationDialog("Rimuovere \(removing?.address ?? "")?", isPresented: isConfirmingRemoval,
                            presenting: removing) { machine in
            Button("Rimuovi Macchina", role: .destructive) {
                Task { await store.remove(machine) }
            }
        } message: { _ in
            Text("Bubo chiude le connessioni e dimentica la Macchina. La chiave resta in ~/.ssh/known_hosts.")
        }
    }

    private func row(for machine: Machine) -> some View {
        let status = store.status(of: machine)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(spacing: Spacing.xSmall) {
                    MachineBadge(machine: machine, status: status)
                    if store.isNew(machine) {
                        Text("nuova")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                detail(for: machine, status: status)
            }
            Spacer()
            actions(for: machine, status: status)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func detail(for machine: Machine, status: MachineStatus?) -> some View {
        let record = store.records[machine.alias]
        if status == .blocked {
            Text("La chiave dell'host è cambiata: Bubo non si connette.")
                .font(.callout)
                .foregroundStyle(Palette.danger)
        } else if let failure = store.failures[machine.alias], !failure.isEmpty {
            Text(verbatim: failure)
                .font(.callout)
                .foregroundStyle(Palette.danger)
                .lineLimit(2)
        } else {
            Text(verbatim: [machine.alias, record?.system, record?.confirmedKey].compactMap(\.self)
                .joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func actions(for machine: Machine, status: MachineStatus?) -> some View {
        if store.connecting == machine.alias {
            LoadingLabel("Connessione…")
        } else if status == .blocked {
            Button("Dettagli…") { details = machine }
            Button("Verifica di nuovo") {
                store.unblock(machine)
                Task { await store.connect(machine) }
            }
            .help("Dopo aver tolto la chiave vecchia da known_hosts")
        } else if status != .connected {
            Button("Connetti") { Task { await store.connect(machine) } }
                .disabled(store.connecting != nil)
        }
        if store.records[machine.alias] != nil, store.connecting != machine.alias {
            Button("Rimuovi Macchina…") { removing = machine }
        }
    }

    /// The question OpenSSH asks; closing its sheet refuses it.
    private var questionBinding: Binding<MachineQuestion?> {
        Binding { store.question } set: { if $0 == nil, store.question != nil { store.answer(nil) } }
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding { removing != nil } set: { if !$0 { removing = nil } }
    }
}

#Preview {
    MachinesSettingsView()
}
